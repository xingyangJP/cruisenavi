# RideLane 技術仕様
バージョン: 1.0.91  
更新日: 2026-02-28

## 1. アーキテクチャ
- Presentation: SwiftUI
- Domain: `NavigationDashboardViewModel`
- Data: MapKit (`MKDirections`, `MKLocalSearch`), CoreLocation, URLSession
- Localization: `SeaNavi/SeaNavi/en.lproj`, `SeaNavi/SeaNavi/ja.lproj`（iOSのアプリ別言語設定に対応）

## 2. 主要フロー
1. `NavigationDashboardView` から目的地検索を開く
2. `DestinationSearchViewModel` が検索種別に応じた距離範囲でスポットを取得（おすすめ: 10〜100km / テキスト検索: 200km圏内）
3. `MapKitRoadRoutePlanner` が道路ルートを段階的リトライで計算
4. `RoutePreviewView` で全体確認後、`DrivingNavigationView` で案内開始
5. `FavoriteDestinationStore` がお気に入り目的地を永続化し、Home/目的地検索の両方で再利用

## 3. ルーティング仕様
- 交通手段候補:
  - 平坦優先: 自動車 → 徒歩（徒歩ルートは階段を含む場合に除外）
  - ヒルクライム: 徒歩 → 自動車（徒歩ルートは階段を含む場合に除外）
- 目的地設定のルートモード選択を `CyclingRouteMode` として保持し、再ルート時も同モードを維持
- `MKDirections` は代替ルート取得を有効化し、平坦優先は短距離寄り、ヒルクライムは長距離寄りで候補選定
- 目的地道路スナップを適用
- ルート失敗時: 300m 超の直線フォールバックは表示しない
- ETA は距離と自転車想定速度（18km/h）から算出

## 4. 位置情報仕様
- 実 GPS を優先
- `ENABLE_MOCK_LOCATION=1` の場合のみモックフォールバック
- 追跡状態を UI に表示（実GPS/フォールバック/位置情報なし）
- 速度は GPS 値優先 + 距離/時間補完で算出し、停止時は 0 表示

## 4.1 ナビ表示/再ルート仕様
- ナビカード右上に「速度」「目的地までの全体道のり」を2段表示
- 次操作地点までの残り距離（旧右上表示）は非表示
- ナビ案内カードは画面下部固定、ズームUIは右上、`終了`/`メニュー` は左上縦アイコン配置
- 全体道のりは走行進捗に合わせてリアルタイム更新
- 通過済みルート線は地図から順次非表示
- 現在地がルートから 35m 超逸脱した場合は自動再ルート（8秒クールダウン）
- `DrivingNavigationView` 表示中は `UIApplication.shared.isIdleTimerDisabled = true` で自動スリープを抑止し、離脱時に解除
- 目的地まで 45m 以内、または残距離 0.08km 以下で到着と判定し、到着メッセージを一度だけ表示（4秒で自動非表示）
- ナビ中は30秒ごとに補給リマインド判定を実行し、速度4km/h以上の走行時のみ表示
- 補給間隔は気温・走行速度・気象警戒レベルから 8〜35分の範囲で動的算出し、バナーに「給水間隔 + 推定消費kcal/h」を表示
- ナビ中は危険地点アラート（MVP）を判定し、急カーブ先読み（約140m以内）、路面悪化（気象警戒/路面リスク）、夜間高速走行を上部バナーで通知
- 危険アラートは連続通知を抑止（18秒クールダウン、同一シグネチャは45秒抑止）

## 4.2 お気に入り目的地仕様
- `FavoriteDestinationStore`（UserDefaults保存）でお気に入りを永続化
- 識別キーは `name + rounded(lat/lon)` で生成し、同一地点の重複保存を防止
- 目的地検索の結果行で `☆` トグルにより保存/解除
- 目的地検索画面の先頭に `お気に入り` セクションを常時表示
- Home に `お気に入りから出発` 横スクロール（最大5件）を表示し、1タップでナビ開始
- お気に入りから開始した場合は `lastUsedAt` を更新して表示順に反映

## 5. 天気仕様
- WeatherKit を第一優先で使用して天候/風速/風向を取得（風速は m/s 表示）
- WeatherKit 失敗時は OpenWeather（`2.5/weather`）へフォールバック
- `ENABLE_MOCK_WEATHER=1` の場合のみモック天気へフォールバック
- WeatherKit の時間予報から「何分後に雨」を算出して表示（取得不可時は非表示）
- OpenWeather One Call でも時間予報 (`hourly.pop`) から最初の降雨時刻を算出
- ナビ/プレビュー中はルート座標（1/4, 1/2, 終点）をサンプリングして30〜60分先降雨を評価
- 30〜60分先降雨を検知した場合は `RainAvoidanceAlert` を発火し、`回避ルート提案` で平坦優先再ルートを実行
- 取得値から `roadRisk` と `warning` を算出
- `WeatherSnapshot` に `temperatureCelsius` を保持し、補給リマインド計算に利用
- 帰属表示として ` Weather` と `https://weatherkit.apple.com/legal-attribution.html` を天気カードに常時表示

## 6. HealthKit 同期
- ナビ終了時に `VoyageLog` を `HKWorkout`（cycling）として保存
- ルートポイントは `HKWorkoutRoute` として保存
- HealthKit 権限は初回同期時に要求

## 7. ビルド
- プロジェクト: `SeaNavi/RideLane.xcodeproj`
- スキーム: `SeaNavi`
- バージョン: `MARKETING_VERSION = 1.0.91`

## 8. オンボーディング（ウォークスルー）
- `NavigationDashboardView` で初回起動時にオーバーレイ型ウォークスルーを表示
- 表示制御は `@AppStorage("onboarding.walkthrough.completed")` を使用し、完了/スキップで再表示を抑止
- シミュレーターのみ `targetEnvironment(simulator)` で毎回表示（QA効率化）
- ステップ構成:
  1. 位置情報有効化（`LocationService.requestAuthorization()`）
  2. Home構成説明
  3. 初回ライド導線（目的地シート起動）
  4. 週次ミッション説明
  5. 完了

## 9. DAU向上機能
- `TodayRideSuggestion`:
  - 周辺候補から天候/風/距離を加味して `今日の1本` を算出し、Homeで1タップナビ開始
  - 候補距離は `10〜50km` を優先
- `WeeklyMissionProgress`:
  - 週単位（`weekOfYear`）で距離を集計し、`今週40km` の進捗を表示
- `RideCompletionReward`:
  - ナビ終了時に新規ログからバッジを生成し、ハイライトシートを表示
- `RestSpotSuggestion`:
  - 当日累計走行距離と気象警戒レベル（none/advisory/warning）から休憩推奨閾値を算出し、Homeに休憩候補を1件表示
  - 候補選定は近場スポットのうち `休憩/給水/自販機/ベンチ/カフェ/コンビニ` キーワード一致を優先
  - CTAからそのスポットへ平坦優先ルートで即ナビ開始
- 補給リマインド:
  - ナビ中の気温・速度・気象警戒に応じ、給水タイミングを動的提示
  - バナー文言は `xx分ごとに給水 / 約xxxkcal/h` で表示し、4秒で自動非表示
- 危険地点アラート（MVP）:
  - 急坂/狭路の地物判定は未対応。まずはルート形状と気象・時間帯から危険兆候を通知
  - バナー文言は `前方急カーブ注意` / `路面悪化注意` / `夜間注意` を使用し、4.5秒で自動非表示
- ライドログ軌跡補完:
  - ライド終了時の取得軌跡が `3点未満` の場合、ナビルート座標で補完してライド詳細地図の直線化を防ぐ
- 到着自動終了:
  - 到着判定（目的地45m以内、または残距離0.08km以下、または残ルート点1以下）成立時に到着バナー表示後、自動でナビ終了してリワード表示へ遷移
- ライドストーリー自動生成（MVP）:
  - ライド詳細画面で `VoyageLog` からタイトル/サブタイトル/ハイライトを組み立てたストーリーカードを表示
  - `ShareLink` でストーリー要約テキストを外部共有可能

## 10. 法務ページ表示仕様
- Home 右上の設定シートから `利用規約` / `プライバシー` を選択して `WKWebView` シートを開く
- 読み込み先URL:
  - `https://lp.xerographix.co.jp/ridelane/terms.html`
  - `https://lp.xerographix.co.jp/ridelane/privacy.html`
- `Application Support/LegalCache` にHTMLを保存し、通信失敗時はキャッシュを表示
- キャッシュがない状態でオフラインの場合は、オフライン案内HTMLを表示
- DOMスクリプトで `RideLane トップへ戻る` 文言を持つリンク/ボタンを非表示化

## 11. Health連携説明・同意仕様
- Home 右上の設定シートの `Health連携について` から説明シートを開く
- 説明シートには `同期するデータ` / `利用目的` / `しないこと` を明記
- トグル `Apple Healthに同期する` がOFFの間は、ナビ終了時にHealthKit保存を実行しない
- OFF時のライドログ状態は `Health連携オフ` として記録

## 12. Firebase Analytics仕様
- `GoogleService-Info.plist` をアプリバンドルに同梱し、`SeaNaviApp` 起動時に `FirebaseApp.configure()` を実行
- `GoogleService-Info.plist` が見つからない場合は初期化をスキップ（DEBUGログのみ出力）
- 利用SDKは `FirebaseAnalytics`（IDFAはアプリ側で利用しない）
- Home初回表示時に `home_view` イベントを1回送信し、`app_version` をパラメータで付与
- ルートプレビュー表示時に `route_preview_open`（`route_mode`, `distance_km`, `eta_min`）を送信
- ナビ開始時に `nav_start`（`route_mode`, `distance_km`, `eta_min`）を送信
- ライド終了時に `ride_complete`（`distance_km`, `avg_speed_kmh`, `badge_count`, `health_sync_enabled`）を送信
