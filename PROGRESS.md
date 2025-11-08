# SeaNavi 開発進捗ログ

## 2025-11-08
- SwiftUI ベースの最小アプリ構成を作成（`SeaNaviApp` エントリ + ダッシュボード画面）
- Navigation / Weather / Logbook / Ports それぞれのプレースホルダービューとサンプル ViewModel を追加
- 要件定義のデータモデル（VoyageLog, WeatherSnapshot, Harbor）をコード化し、ダッシュボードにバインド
- README_TEST.md をドラフトし、シミュレータでのテストフロー叩き台を準備

## 2025-11-09
- `LocationService` を実装し、CoreLocation／MockRouteProvider の再生でルートポイントを生成
- `SeaMapView` を追加し、MapKit のユーザ位置／ポリライン／浅瀬ポリゴン表示を実現
- `WeatherAPIClient` / `TideAPIClient` の骨組みと Mock サービスを用意し、Dashboard VM から `async/await` でフェッチ
- HUD を位置情報・気象データにリアクティブ連携、警告メッセージのフェイルセーフを追加
- README_TEST.md を v0.2 へ更新（MapKit / API テストケース追記）

### 次のステップ候補
1. 実 API キーを読み込む Config レイヤと Secrets 管理フローの整備
2. 浅瀬ポリゴンとの距離計算ロジックを実装し、警告の判定を実データ化
3. UI テーマを DesignToken 化し、GlassCard コンポーネントを共通モジュールに抽出
4. README_TEST.md のケースを自動化（XCUITest・位置シミュレーションスクリプト）
