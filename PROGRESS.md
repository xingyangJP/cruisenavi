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
- Config ディレクトリとサンプル plist を追加し、Weather API キーの外部化と loader 実装を完了
- OpenWeather One Call / Open-Meteo Marine API と接続し、リアル風速・潮位・警報ロジックをアプリに反映
- TideWeatherCard にソース表示とリアル潮汐の表示ロジックを追加、README_TEST.md v0.3 で検証手順を更新

## 2025-11-10
- 目的地セット時にルートプレビュー（全画面マップ + スタート/キャンセル）を表示するフローを追加
- RoutePreviewView を実装し、DrivingNavigationView との遷移を分離
- RouteSummary / NauticalRoutePlanner / RoutingWaypoint を追加し、最寄り港/海岸と候補ウェイポイントから航路を構築
- SplashView をロゴフェード演出に調整

### 次のステップ候補
1. 浅瀬ポリゴン・海岸線データを取得し、A* などで実航路を生成
2. Driving/Preview UI へ音声案内・ターン指示を追加
3. README_TEST.md のケースを自動化（XCUITest・位置シミュレーションスクリプト）
4. Map/Tide/Weather のエラーログを OSLog + Telemetry パイプラインに集約
