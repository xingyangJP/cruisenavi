# Ranking Mode Plan

> ステータス: 設計のみ（実装未着手）。フリーライドの拡張機能として位置づける。
> 関連: [FREE_CYCLING_MODE_PLAN.md](FREE_CYCLING_MODE_PLAN.md)

## 1. 目的
- 走行記録に「競う」価値を追加し、継続動機を強化する
- 2軸のランキングを提供する
  - 最長連続走行距離（1ライドの総距離）
  - 最高速度
- それぞれ「自分ランキング（自己ベース/履歴）」と「全世界ランキング」を提供する
- 車・電車などの乗り物移動を記録に混入させない（不正防止）

## 2. 対象スコープと段階
今回の決定事項：

| 項目 | 決定 |
|---|---|
| 初期スコープ | まず設計書のみ（本ドキュメント） |
| 不正防止 | 端末側のみ（軽量） |
| 「最長連続距離」の定義 | 1ライドの総距離 |

段階（ロードマップは §9）：
- フェーズA: 自分ランキング（端末内データのみ、バックエンド不要）
- フェーズB: 全世界ランキング（Firestore＋認証の新規構築が必要）

> 注意: 不正防止を「端末側のみ」とした場合、フェーズB（公開ランキング）では端末改ざんによる詐称を完全には防げない。フェーズB公開前に §4.4 のサーバー検証を追加することを推奨（未決事項 §10）。

## 3. ランキング定義

### 3.1 最長連続走行距離
- 単位: km
- 定義: 開始〜終了の**1セッション（1ライド）で走行した総距離**
- 一時停止をはさんでも同一ライドなら継続扱い
- 集計元: `VoyageLog.distance`（不正区間を除外した有効距離。§4.3）
- 自分ランキング: 自己ベスト＋距離順の履歴一覧
- 全世界ランキング: 有効ライドの距離降順

### 3.2 最高速度
- 単位: km/h
- 定義: ライド中に到達した最高速度。ただし**GPSスパイク対策として「N秒間継続した速度のピーク」**を採用する（瞬間1点値は不採用）
  - 推奨: `sustainedWindow = 3秒`
- 上限キャップ: 自転車として非現実な値は無効化（推奨 `maxPlausibleKmh = 90`。超過区間は不正扱い §4.2）
- 集計元: 新規追加する `VoyageLog.maxSustainedSpeed`（§5）
- 全世界ランキング: 有効ライドの最高速度降順

> 安全性メモ: 最高速度ランキングは危険走行を助長しうる。UIに減速・安全の注意文言を添え、達成演出は「下り区間の記録」等トーンを抑える（§8.2）。

## 4. 不正防止（端末側のみ）
単一判定は破られやすいため、端末内で複数シグナルを重ねる。

### 4.1 活動種別フィルタ（CoreMotion）
- `CMMotionActivityManager` を用い、走行中の各時刻の活動種別を取得
  - `.cycling` / `.walking` / `.running` / `.automotive` / `.stationary` / `unknown`
- `.automotive`（および `.stationary` でない高速移動）と判定された区間の GPS 点を**有効区間から除外**
- 端末対応可否: `CMMotionActivityManager.isActivityAvailable()` を確認。非対応端末は §4.2 の速度サニティのみで判定
- 権限: モーションとフィットネス（`NSMotionUsageDescription`）を Info.plist に追加

### 4.2 速度サニティチェック
- 瞬間速度 > `maxPlausibleKmh`（90km/h）は無効サンプル
- 巡航（例: 50km/h 超が一定時間継続）かつ `.cycling` 未確定の区間は「乗り物疑い」フラグ
- 加速度の妥当性: 自転車で不可能な短時間加速（例: 数秒で 0→60km/h）は無効
- 既存の `SpeedNormalizer`（[LocationService.swift](../Sources/Services/Location/LocationService.swift)）を活かし、しきい値判定を追加する層として設計

### 4.3 有効区間・有効距離の算出
- ライドの GPS 軌跡を「有効サンプル」と「除外サンプル」に分類
- 有効距離 = 有効区間のみの積算距離
- ランキング対象の距離・最高速度は**有効区間のみ**から計算
- 除外率が高いライド（例: 有効サンプル < 60%）は「記録対象外」とし、UIで理由を明示

### 4.4 サーバー検証（フェーズB・今回スコープ外）
公開ランキングでは端末値を信用できないため、将来的に以下を追加：
- 送信された GPS 軌跡・活動種別からサーバー側で距離/速度を**再計算**
- 統計的外れ値の検出、上限キャップ、レート制限
- 疑わしい記録のフラグ・保留・除外

## 5. データモデル設計

### 5.1 `VoyageLog` の拡張
既存 [VoyageLog.swift](../Sources/Models/VoyageLog.swift) に追加（すべて Optional でマイグレーション安全に）：

```swift
struct VoyageLog {
    // 既存: id, startTime, endTime, routePoints, distance, averageSpeed, weatherSummary, mode
    let maxSustainedSpeed: Double?      // 3秒継続ピーク速度 km/h（有効区間のみ）
    let effectiveDistance: Double?      // 不正区間を除いた有効距離 km
    let validSampleRatio: Double?       // 有効サンプル比率 0.0-1.0
    let isRankingEligible: Bool?        // ランキング集計対象か
    let activityBreakdown: [String: Double]? // 活動種別ごとの時間割合（監査用）
}
```
- 永続化は既存の `PersistedVoyageLog`（[NavigationDashboardViewModel.swift](../Sources/Features/Navigation/NavigationDashboardViewModel.swift)）に対応フィールドを追加。旧データは Optional=nil で読み込み可能に。

### 5.2 集計モデル（フェーズA・ローカル）
```swift
enum RankingMetric { case longestDistance, topSpeed }

struct PersonalRankingEntry: Identifiable {
    let id: UUID            // VoyageLog.id
    let rank: Int
    let value: Double       // 距離 or 速度
    let date: Date
    let mode: VoyageLogMode
}

struct PersonalRankingBoard {
    let metric: RankingMetric
    let best: PersonalRankingEntry?
    let entries: [PersonalRankingEntry]   // 上位N（距離/速度降順）
}
```

### 5.3 全世界ランキング（フェーズB・Firestore設計案）
```
collection: leaderboards/{metric}/entries/{userId}
  - userId (Sign in with Apple の安定ID)
  - displayName        // 公開名（本名不可、任意）
  - value              // ベスト距離 or ベスト速度
  - achievedAt
  - rideId
  - verified: Bool     // サーバー検証済みフラグ（フェーズBで有効化）
  - country / region   // 任意（地域別ランキング用）
```
- 認証: **Sign in with Apple 推奨**（匿名認証は詐称・多重登録に弱い）
- 送信は自己ベスト更新時のみ（コスト最小化）
- 読み取りは Top100＋自分順位のクエリ

## 6. アーキテクチャ
- **自分ランキング（フェーズA）**: 既存の `voyage_logs.json` を集計するだけ。ネットワーク不要・最速・低リスク。新規 `RankingService`（純ロジック）を追加し、`NavigationDashboardViewModel` から供給
- **不正防止**: `RideIntegrityAnalyzer`（新規）を導入。`LocationService` の GPS＋CoreMotion を受け取り、有効区間/有効距離/最高継続速度/eligibility を算出。ライド終了時 `finalizeRideLogIfNeeded()` で呼び出し、`VoyageLog` に反映
- **全世界ランキング（フェーズB）**: `WorldRankingService`（Firestore）。認証・送信・取得・キャッシュを担当。既存の `RideLogSyncService`（Health同期）と同じ「終了時同期」パターンに合わせる

## 7. UI/UX設計
- 入口: ホームに「ランキング」導線（フリーライド完了リワードからも遷移）
- ランキング画面
  - 上部タブ: `距離` / `速度`
  - スコープ切替: `自分` / `世界`（世界はフェーズBまで「準備中」表示）
  - 自己ベストカード（大きな数字＋達成日）＋履歴リスト（順位・値・日付・モードバッジ）
  - 世界: Top100リスト＋自分の順位をピン留め表示
- ライド完了時: 「自己ベスト更新！」演出（距離/速度）を既存リワード（`RideCompletionReward`）に統合
- 記録対象外だった場合: 「乗り物移動を検知したため一部を記録対象外にしました」と理由を明示（信頼感のため透明に）

## 8. プライバシー・安全性
### 8.1 プライバシー
- 世界ランキングは**明示的オプトイン**。OFFなら送信しない
- 公開するのは値・表示名・達成日のみ。**GPS軌跡は公開しない**
- 表示名は任意入力（本名を強制しない）。既存プライバシーポリシー/利用規約への追記が必要
- 位置・モーションデータの利用目的を権限ダイアログと設定画面で説明

### 8.2 安全性
- 最高速度ランキングに安全注意文言を常設
- 達成演出は煽らないトーン
- 速度の非現実値は自動無効化（§4.2）で「無謀運転の見かけ上の記録」を抑制

## 9. ロードマップ
1. フェーズA-1: `RideIntegrityAnalyzer`（CoreMotion＋速度サニティ）と `VoyageLog` 拡張
2. フェーズA-2: `RankingService`（自分ランキング）＋ランキング画面（距離/速度・自分）
3. フェーズA-3: ライド完了の自己ベスト演出統合
4. フェーズB-1: Sign in with Apple 導入＋Firestoreスキーマ
5. フェーズB-2: 送信/取得＋世界ランキングUI
6. フェーズB-3: サーバー検証（§4.4）と不正フラグ運用

## 10. リスク・未決事項
- 端末側のみの不正防止は公開ランキングで詐称を許容しうる → フェーズB公開前にサーバー検証を要検討
- CoreMotion 未対応端末・権限拒否時のフォールバック方針（速度サニティのみで運用するか、ランキング対象外にするか）
- 「最高速度」演出と安全配慮のバランス（審査・法務観点の確認）
- Firestore のコスト設計（読み取り課金・Top100キャッシュ戦略）
- 表示名の不適切語対策（モデレーション）
- 世界ランキングの地域/期間区分（全期間のみか、週間/月間も持つか）
