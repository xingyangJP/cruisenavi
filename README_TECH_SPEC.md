# Navis 技術仕様書（README_TECH_SPEC.md）
バージョン: 1.0  
作成日: 2025-11-08  
作成者: Yukihiro  

---

## 1. ドキュメント目的
Navis（iOS航行ナビアプリ）の実装・運用に必要な技術要件を網羅する。要件定義書（README.md）とUI設計書（README_UI.md）を統合し、アーキテクチャ・データフロー・開発ルールを本書で参照できるようにする。

---

## 2. システム全体像

| レイヤ | 技術 | 役割 |
|--------|------|------|
| プレゼンテーション | SwiftUI, WidgetKit, Live Activities | UI描画、ガラスマテリアル表現、Dynamic Island拡張 |
| ドメイン | Combine, Swift Concurrency, NavigationUseCase | 航行計算、危険判定、潮汐解析ロジック |
| データ | CoreData, iCloudKit, URLSession, MapKit, CoreLocation, CoreMotion | データ取得・保存、地図描画、センサー連携 |

アプリはオフライン動作を前提に、オンライン時は REST API（気象庁・海保・OpenWeather 等）からデータを同期する。MapKit カスタムタイルで海図を重ね、CoreLocation で航跡を追跡する。

---

## 3. アーキテクチャ指針
- **モジュール分割**: Feature（Navigation, Safety, Weather, Log, Port, Emergency）単位で分離し、共通UIは `DesignSystem` モジュールに隔離。
- **状態管理**: `@State`, `@StateObject`, `@EnvironmentObject` + Combine によるリアクティブ更新。Live Activities へのブリッジは ActivityKit wrapper で抽象化。
- **非同期処理**: `async/await` と `Task` を標準化。API呼び出しは `APIClient` で retry / exponential backoff を実装。
- **オフラインファースト**: APIレスポンスは CoreData にキャッシュ、海図タイルはオンデマンドダウンロードして `URLCache` で保持。通信断時は最新キャッシュを利用。
- **Dependency Injection**: Protocol指向（`NavigationRepository`, `WeatherRepository` 等）でテスト容易性を確保。

---

## 4. 主要機能別技術仕様

- **センサー**: CoreLocation (1s interval), CoreMotion (傾きで背景パララックス)
- **ルーティング**: ENC / GeoJSON から抽出した海上ノード／航路チャネルをグラフ化し、A* で最短海上ルートを算出。現在地 → 最寄り港/海岸ノード → 目的地の順で接続し、陸地ポリゴンや浅瀬ポリゴンはヒューリスティックで回避。ETA は `CLGeodesic` と潮流補正で算出。
- **ルートプレビュー**: 目的地決定後に全航路をフルスクリーンで表示し、スタート地点とゴールカードを提示。ユーザーが「スタート」を押すと Driving HUD へ遷移。
- UI: Home画面上部に NavigationHUD（GlassCard）を固定表示、Live Activities へ速度/ETAを更新。
- Map: MapKit Overlays + Custom Renderer で浅瀬/航行禁止区域を描画。進行方向は `MKAnnotation` の heading を利用。

### 4.2 浅瀬・危険区域警告
- データ: ENC/GeoJSON を CoreData に格納。ポリゴンとの距離計算で閾値以内なら警報。
- 通知: Haptic (警報のみ), `UNUserNotificationCenter` + 音声読み上げ (AVSpeechSynthesizer)。
- UI: マップ上に赤色 Overlay、HUDに警告ラベル。設定画面で閾値をスライダー調整。

### 4.3 気象・潮汐データ
- API: 気象庁 (潮位), 海上保安庁 (潮流), OpenWeather (風速/波高)。
- 更新: 60秒ごとにバックグラウンド `BGAppRefreshTask` でフェッチ。失敗時は前回値を保持。
- 表示: Swift Charts の `LineMark` / `AreaMark` で潮位、`BarMark` で風速。ガラスカード内に配置。

### 4.4 クルーズログ
- 記録: 30秒間隔で GPS サンプルを `route_points` に追記。写真は `PHPhotoLibrary` 経由で URL 保存。
- データ同期: iCloudKit で multi-device 共有。コンフリクトは最新タイムスタンプ優先。
- リプレイ: `TimelineView` で時系列再生、Map 上で Polyline を描画。

### 4.5 港湾・地域情報
- データ: 国交省APIを週次で取得し JSON キャッシュ。お気に入りは CoreData で管理。
- UI: GlassCard リスト + SF Symbols。地域タブを `SegmentedControl` + `.thinMaterial` 背景で切替。
- ルートプレビュー: 目的地をセットした時点でフルスクリーンのルートプレビューを表示し、起点〜目的地の全体ラインと「スタート」ボタンを提示。ユーザーがスタートを押すとナビゲーションHUD/Drivingモードへ遷移。

### 4.6 緊急サポート
- ボタン: 常時表示の大型 `.regularMaterial` ガラスボタン。`callkit://118` をトリガ。
- 自動テキスト: 現在地・速度・進行方向をテンプレートに差し込み、共有シートで送信可能。
- アクセシビリティ: `accessibilityLabel` 明示、VoiceOver で即座に選択可能。

---

## 5. UI / デザイン実装

### 5.1 デザインシステム
- GlassCard, NavigationHUD, TideChartCard, EmergencyButton をコンポーネント化し再利用。
- カラー/タイポは `DesignToken`（enum + computed property）で集中管理。
- モーション: `phaseAnimator`, `.spring()`, `.easeInOut` を用途別にプリセット化。

### 5.2 カラーパレット
DeepSea Blue (#00334E), Aqua Teal (#36C2CF), Silver Mist (#E1E4E8), Night Navy (#0D1B2A), Wave Cyan (#6EE2F5)。画面ごとに強調色は Aqua Teal を1要素に限定。

### 5.3 アニメーション方針
- 背景: CoreMotion + `rotation3DEffect` で緩やかな揺れ。
- HUD更新: `withAnimation(.easeInOut(duration: 0.4))`。
- ボタン: `withAnimation(.spring(response:0.4,dampingFraction:0.8))`。
- 起動: `.opacity` + `.blur` でフェードイン、海上の静けさを演出。

### 5.4 アクセシビリティ
- Dynamic Type 対応 (font modifiers), VoiceOver ラベル完備, コントラストは material + overlay で確保。
- 片手親指操作を想定し、主要ボタンは下部に配置。

---

## 6. データモデル

### 6.1 航行ログ
```
struct VoyageLog {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let routePoints: [CLLocationCoordinate2D]
    let distance: Double
    let avgSpeed: Double
    let notes: String
    let photos: [URL]
    let weatherSummary: String
}
```

### 6.2 気象データ
```
struct WeatherSnapshot {
    let timestamp: Date
    let tideHeight: Double
    let tideState: TideState
    let windSpeed: Double
    let windDirection: Double
    let waveHeight: Double
    let warning: WarningLevel?
}
```

### 6.3 港湾情報
```
struct Harbor {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let facilities: [HarborFacility]
    let restrictions: [String]
}
```

---

## 7. 外部API / データ連携

| 種別 | API | エンドポイント例 | 更新頻度 |
|------|-----|------------------|----------|
| 潮汐 | 気象庁 Tide API | `/tide/{stationId}` | 1分 |
| 気象 | OpenWeather Marine | `/data/3.0/onecall` | 5分 |
| 海図 | 海上保安庁 ENC | S57タイル | 週次 |
| 港湾 | 国交省 港湾設備 | `/harbors` | 週次 |
| 緊急 | 音声通話 118 | URLスキーム | 随時 |

APIクライアントは TLS 1.3 / Cert Pinning を実装し、データは JSONDecoder で `Decodable` モデルへマッピングする。

---

## 8. 非機能要件

| 項目 | 要件 |
|------|------|
| パフォーマンス | GPS追跡 + Map更新を60fps維持（`CADisplayLink`で監視） |
| 電力 | `reducedAccuracy` 位置更新モードを航行外で使用しバッテリー節約 |
| セキュリティ | KeychainでAPIキー保護、全通信TLS1.3 |
| 可用性 | キャッシュ済み海図とログで通信断でも航行継続 |
| 拡張性 | 新海域/センサーはリポジトリ追加で対応 |
| UX統一 | Apple HIG + Glass体系順守 |

---

## 9. ビルド / デプロイ
- Xcode 17+ / Swift 6。Package Manager で依存関係管理（例: Swift Algorithms）。
- ビルドターゲット: iOS 18 (Base) / iOS 25 最適化。
- CI: GitHub Actions → fastlane → TestFlight 配信。`xcodebuild test` → `swiftlint` → `sonar` の順で実行。
- 証明書: Apple Developer Enterprise。Provisioning Profiles は自動管理。

---

## 10. テスト戦略
- Unit: UseCase / Repository に対し XCTest + Mock API。
- Snapshot: SwiftUI SnapshotTesting で Glass UI の視覚リグレッション検知。
- Integration: CoreLocation/MapKit を `simctl` でリプレイし航行ルートを再現。
- UI自動: XCUITest で航行シナリオ、警報、緊急通報導線を検証。
- 負荷: `xctrace` で 3時間航行時のメモリ/電力を測定。

---

## 11. ログ / 監視
- ログ: `OSLog` + `Logger`、カテゴリ（navigation/weather/emergency）別に出力。
- クラッシュ: Xcode Organizer + Firebase Crashlytics（オフラインでもバッファリング）。
- 分析: ローカルでのみ航行統計を算出、PIIを外部送信しない。

---

## 12. セキュリティ・プライバシー
- 位置情報はオンデバイスに暗号化保存（SQLCipher for CoreData）。
- iCloud同期データに対し CloudKit Role でアクセス制限。
- 緊急通報ログは端末内に限定し自動削除（30日）。
- アプリ権限（Location, Motion, Notification, Photo）はオンボーディングで説明。

---

## 13. 将来拡張
- Vision Pro: RealityKit で航跡3D可視化。
- Bluetooth: 外部センサー接続フレームワークを `PeripheralManager` として追加。
- AI航路: CoreML + 気象履歴で安全経路提案。
- 共有ログ: CloudKit Public DB でログ共有、匿名メタデータのみ送信。

---

本仕様書は README.md / README_UI.md の要件を技術視点で再構成したものであり、開発時は本書をベースに詳細設計・実装を進める。
