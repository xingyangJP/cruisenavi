# RideLane 技術仕様
バージョン: 1.0.39  
更新日: 2026-02-15

## 1. アーキテクチャ
- Presentation: SwiftUI
- Domain: `NavigationDashboardViewModel`
- Data: MapKit (`MKDirections`, `MKLocalSearch`), CoreLocation, URLSession

## 2. 主要フロー
1. `NavigationDashboardView` から目的地検索を開く
2. `DestinationSearchViewModel` が 100km 圏内スポットを取得
3. `MapKitRoadRoutePlanner` が道路ルートを段階的リトライで計算
4. `RoutePreviewView` で全体確認後、`DrivingNavigationView` で案内開始

## 3. ルーティング仕様
- 交通手段候補: 自動車 → 徒歩（徒歩ルートは階段を含む場合に除外）
- 目的地道路スナップを適用
- ルート失敗時: 300m 超の直線フォールバックは表示しない
- ETA は距離と自転車想定速度（18km/h）から算出

## 4. 位置情報仕様
- 実 GPS を優先
- `ENABLE_MOCK_LOCATION=1` の場合のみモックフォールバック
- 追跡状態を UI に表示（実GPS/フォールバック/位置情報なし）

## 5. 天気仕様
- WeatherKit を第一優先で使用して天候/風速/風向を取得（風速は m/s 表示）
- WeatherKit 失敗時は OpenWeather（`2.5/weather`）へフォールバック
- `ENABLE_MOCK_WEATHER=1` の場合のみモック天気へフォールバック
- WeatherKit の時間予報から「何分後に雨」を算出して表示（取得不可時は非表示）
- 取得値から `roadRisk` と `warning` を算出

## 6. HealthKit 同期
- ナビ終了時に `VoyageLog` を `HKWorkout`（cycling）として保存
- ルートポイントは `HKWorkoutRoute` として保存
- HealthKit 権限は初回同期時に要求

## 7. ビルド
- プロジェクト: `SeaNavi/RideLane.xcodeproj`
- スキーム: `SeaNavi`
- バージョン: `MARKETING_VERSION = 1.0.39`
