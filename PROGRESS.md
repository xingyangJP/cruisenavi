# SeaNavi 開発進捗ログ

## 2025-11-08
- SwiftUI ベースの最小アプリ構成を作成（`SeaNaviApp` エントリ + ダッシュボード画面）
- Navigation / Weather / Logbook / Ports それぞれのプレースホルダービューとサンプル ViewModel を追加
- 要件定義のデータモデル（VoyageLog, WeatherSnapshot, Harbor）をコード化し、ダッシュボードにバインド
- README_TEST.md をドラフトし、シミュレータでのテストフロー叩き台を準備

### 次のステップ候補
1. MapKit + CoreLocation の実データ配線（現在はダミー表示）
2. 潮汐 / 気象 API クライアント層の雛形追加
3. UI テーマを DesignToken 化し、GlassCard コンポーネントを独立モジュール化
4. README_TEST.md のケースを自動化（XCUITest シナリオ雛形）
