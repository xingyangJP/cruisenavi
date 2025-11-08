# SeaNavi テスト手順書（README_TEST.md）
バージョン: 0.2  
更新日: 2025-11-08  

本書は SeaNavi iOS アプリの機能検証を **Xcode シミュレータ** 上で実施するための手順をまとめたものです。README.md / README_TECH_SPEC.md に定義された要件を基準に、現状開発済みの範囲に応じてテストケースを追記していきます。

---

## 1. 前提条件
1. macOS 14 Sonoma 以降
2. Xcode 17 以降（Swift 6 toolchain）
3. iOS 18 シミュレータ（iPhone 15 Pro 推奨）
4. 必要な API キー・モックデータ（潮汐/気象/港湾）を `Config/` ディレクトリに配置済み

---

## 2. テスト環境セットアップ
1. リポジトリをクローン  
   ```bash
   git clone https://github.com/xingyangJP/cruisenavi.git
   cd cruisenavi
   ```
2. Xcode で `SeaNavi.xcodeproj`（または `.xcworkspace`）を開く  
   - まだ存在しない場合は `File > New > Project…` で SwiftUI App を作成し、`Sources/` 以下のファイルをプロジェクトに追加する
3. ターゲットを `SeaNavi (iOS)`、シミュレータを `iPhone 15 Pro (iOS 18)` に設定
4. `Command + R` でビルド＆起動し、位置情報の許可ダイアログを「許可」に設定
5. `Debug > Location` で `Freeway Drive` または自作 GPX (`Resources/GPX/tokyo_bay_route.gpx`) を選択
6. 気象 API を実機で試す場合は `Config/Weather.plist` に `baseURL` と `apiKey` を登録し、`WeatherAPIConfiguration` に読み込ませる

---

## 3. 共通チェックリスト
- 起動時フェードインアニメーションが 1 秒以内に完了する
- GlassCard / HUD のマテリアル効果が有効
- Dynamic Type のサイズ変更でレイアウトが崩れない
- VoiceOver を ON にして主要ボタンのラベルが適切に読まれる

---

## 4. 機能別テストシナリオ

### 4.1 航行ナビゲーション / MapKit 表示
1. `Debug > Location > Freeway Drive` を選択し、現在地アノテーションとルートポリラインが 1 秒周期で更新されるか確認
2. `MockRouteProvider` の配列が最後まで到達すると循環すること、および `routePoints` カウンタが HUD 下のラベルに反映されることを確認
3. 進行方向（course）が `NavigationHUDView` に 3 桁の角度で表示されること、速度が 0 未満にならないことを確認
4. `MockRestrictedArea` のポリゴンが赤色レイヤーで描画され、視覚的に浅瀬領域を区別できることを確認

### 4.2 浅瀬・危険区域警告
1. テスト用 GPX（浅瀬接近コース）を読み込み
2. 航行禁止ポリゴンに 100m 以内で HUD に赤色警告が表示され、Haptic が 1 回発火
3. 設定画面で閾値スライダーを変更し、即座に警告距離が反映される

### 4.3 気象・潮汐（API クライアント）
1. モック API サーバを起動 (`mock/weather_server.sh start`) し、`WeatherAPIConfiguration` の `baseURL` をモックに向ける
2. 起動後 1 回目の `Task` で `WeatherSnapshot` が更新されること、60 秒ごとに再フェッチが走ることを Xcode の `Debug > View Debugging > View Value` で確認
3. API を停止させ、警告ラベルに「気象データ更新に失敗」と表示されるフォールバックを確認
4. `TideAPIClient` を `MockTideService` から差し替えた場合でも `TideReport` の値が UI へ渡せる（Console ログ出力）ことを確認

### 4.4 クルーズログ
1. 航行開始ボタンを押下し 5 分間シミュレーションを走らせる
2. ログ一覧画面に最新航行が追加され、距離 / 平均速度が正しく算出
3. 写真添付が可能（シミュレータのカメラロールから選択）で iCloud 同期が成功する

### 4.5 港湾・地域情報
1. 港湾タブで地域セグメントを切り替え、リストが正しい件数に変わる
2. 各港カードの SF Symbol が用途に応じて変化（給油所 / 係留）
3. お気に入り登録後、ホーム画面の目的地候補に反映される

### 4.6 緊急サポート
1. Emergency ボタンをタップし、確認ダイアログ → `callkit://118` スキームが起動するかを確認（シミュレータでは失敗ダイアログで可）
2. 共有シートで自動生成された通報テンプレートに現在地・速度が含まれる

---

## 5. 不具合報告テンプレート
```
### 概要
例: 浅瀬警告が Live Activities に反映されない

### 発生手順
1. Xcode 17 / iOS 18 シミュレータ起動
2. ・・・

### 期待結果

### 実際の結果

### ログ / スクリーンショット
```

---

## 6. 今後の追加予定
- Vision Pro / Bluetooth 機能のテストケース
- 長時間航行（連続 3h）でのメモリリーク検知手順
- 自動化（XCUITest）シナリオの手順化

本ファイルは開発進捗にあわせて更新すること。
