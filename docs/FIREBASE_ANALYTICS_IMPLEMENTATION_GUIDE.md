# Firebase Analytics 実装ガイド（iOS 汎用）

最終更新: 2026-02-28
対象: 任意の iOS アプリ（SwiftUI / UIKit）

## 1. 目的
- 主要導線の利用状況を計測し、改善サイクルを回す
- 画面到達率、機能利用率、完了率を可視化する

## 2. 前提
- Firebase プロジェクト作成済み
- 対象 iOS アプリが Firebase に登録済み（Bundle ID 一致）
- `GoogleService-Info.plist` を取得済み
- Xcode + Swift Package Manager を利用

## 3. 導入手順

### 3.1 SDK 追加（SPM）
1. Xcode: `File > Add Package Dependencies...`
2. URL: `https://github.com/firebase/firebase-ios-sdk`
3. Product: `FirebaseAnalytics`
4. 対象ターゲットへリンク

補足:
- バージョンにより product 名が変わるケースがあるため、追加画面に表示される最新 product 名を優先する。

### 3.2 設定ファイル配置
1. `GoogleService-Info.plist` をプロジェクトへ追加
2. `Build Phases > Copy Bundle Resources` に含まれることを確認
3. マルチ環境（Dev/Stg/Prod）はターゲット・構成ごとに plist 切替ルールを定義

### 3.3 起動時初期化（SwiftUI）
```swift
import SwiftUI
import FirebaseCore
import FirebaseAnalytics

@main
struct MyApp: App {
    init() {
        Self.configureFirebaseIfPossible()
    }

    private static func configureFirebaseIfPossible() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("GoogleService-Info.plist not found. Firebase disabled.")
            #endif
            return
        }
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 3.4 起動時初期化（UIKit）
```swift
import UIKit
import FirebaseCore
import FirebaseAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            Analytics.setAnalyticsCollectionEnabled(true)
        }
        return true
    }
}
```

## 4. イベント設計

### 4.1 命名ルール
- 英小文字 + スネークケース
- 例: `screen_viewed`, `cta_tapped`, `onboarding_completed`, `purchase_completed`

### 4.2 パラメータルール
- 同義の値は同じキー名に統一
- 数値は数値型で送る
- PII（メール、電話、正確な住所等）は送らない

### 4.3 最低限の初期イベントセット（推奨）
- `app_opened`
- `screen_viewed`
- `primary_action_tapped`
- `flow_completed`
- `flow_failed`

## 5. 実装テンプレート

### 5.1 直接送信
```swift
Analytics.logEvent("screen_viewed", parameters: [
    "screen_name": "home",
    "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
])
```

### 5.2 ラッパー経由（推奨）
```swift
import FirebaseAnalytics

enum AppAnalytics {
    static func appOpened(version: String) {
        Analytics.logEvent("app_opened", parameters: [
            "app_version": version
        ])
    }

    static func screenViewed(name: String) {
        Analytics.logEvent("screen_viewed", parameters: [
            "screen_name": name
        ])
    }

    static func primaryActionTapped(action: String, screen: String) {
        Analytics.logEvent("primary_action_tapped", parameters: [
            "action_name": action,
            "screen_name": screen
        ])
    }

    static func flowCompleted(flow: String, durationSec: Int) {
        Analytics.logEvent("flow_completed", parameters: [
            "flow_name": flow,
            "duration_sec": durationSec
        ])
    }
}
```

## 6. 検証手順

### 6.1 DebugView
- Firebase Console > Analytics > DebugView を開く
- 実機でイベントを発火し、リアルタイム着弾を確認

### 6.2 最低確認チェック
- アプリ起動で `app_opened` が送信される
- 主要画面遷移で `screen_viewed` が送信される
- 主要CTAで `primary_action_tapped` が送信される
- 完了時に `flow_completed` が送信される

### 6.3 失敗時チェック
- `GoogleService-Info.plist` の同梱漏れ
- Firebase Console 側の Bundle ID 不一致
- イベント名の表記ゆれ

## 7. App Store 申請時の注意
- App Privacy（データ収集申告）を実装内容と一致させる
- 収集目的と利用範囲をアプリ内説明・ポリシーと整合させる
- ATT 要否は利用 SDK/用途に応じて法務方針で判断

## 8. 運用ルール
- イベント追加時は同時に更新:
  1. 計測仕様書（イベント名/パラメータ）
  2. QA項目（発火タイミング）
  3. 分析ダッシュボード（KPI）
- 既存イベント名の変更は原則禁止（時系列比較が壊れる）
- 廃止時は `deprecated` として段階停止

## 9. 実装チェックリスト
- [ ] `FirebaseAnalytics` がターゲットにリンクされている
- [ ] `GoogleService-Info.plist` がバンドルされる
- [ ] 起動時に `FirebaseApp.configure()` が呼ばれる
- [ ] 初期イベントが DebugView で観測できる
- [ ] App Privacy 設定が実装と一致している
