 SeaNavi UI設計書（README_UI.md）
バージョン: 1.0  
作成日: 2025-11-08  
作成者: Yukihiro  

---

## 🎨 デザインコンセプト

> **テーマ:** “Glass meets Ocean”  
> 深海の透明感、航行の静けさ、Apple UIの精密さを融合した  
> 「海上のガラスナビゲーション」体験を提供する。

SeaNavi は、iOS 25 純正の **Material・Motion・Depthデザイン体系** に従い、  
透明感・奥行き・浮遊感を組み合わせた UI を採用する。  
全体トーンは「AquaGlass」を基調とし、波や風を感じさせる流体的なアニメーションを実装する。

---

## 🧩 デザイン指針

| 要素 | 技術 / 機能 | 目的 |
|------|----------------|------|
| マテリアル効果 | `.ultraThinMaterial`, `.thinMaterial` | ガラス風の層構造 |
| 動的奥行き | `rotation3DEffect` + `CoreMotion` | 船上の揺れ・浮遊感 |
| 波の動き | `phaseAnimator` | 水面のゆらぎ表現 |
| グラフ | `Charts` フレームワーク | 潮位・風速・波高の視覚化 |
| 状態表示 | `Live Activities` / `WidgetKit` | Dynamic Island対応 |
| フォント | SF Pro Rounded / SF Pro Display | 優しさ＋視認性 |
| カラー | DeepSea Blue / Aqua Teal / Silver Mist | 海と光の調和 |
| アイコン | SF Symbols | iOSネイティブ統一性 |
| モーション | `.spring()`, `.easeInOut`, `.opacity` | 穏やかな流れを演出 |

---

## 🌊 カラーパレット

| 名称 | HEX | 用途 |
|------|------|------|
| **DeepSea Blue** | `#00334E` | 背景ベース・深海トーン |
| **Aqua Teal** | `#36C2CF` | 強調要素（ボタン、強調ラベル） |
| **Silver Mist** | `#E1E4E8` | フォント／グラス境界線 |
| **Night Navy** | `#0D1B2A` | ダークモード背景 |
| **Wave Cyan** | `#6EE2F5` | グラデーションハイライト |

---

## 🧱 コンポーネント設計

### 1. ガラスカード（GlassCard）

| 要素 | 実装 | 用途 |
|------|------|------|
| 背景 | `.background(.ultraThinMaterial)` | 情報カード全般 |
| 角丸 | `cornerRadius(24)` | 柔らかさと安全感 |
| 影 | `.shadow(radius: 12, y: 8)` | 浮遊感 |
| 境界線 | `.overlay(.white.opacity(0.1))` | ガラス縁を表現 |
| モーション | `.phaseAnimator` で微揺れ | 海上らしさの演出 |

```swift
struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1)))
                .shadow(radius: 12, y: 8)
            content.padding()
        }
    }
}


⸻

2. 航行情報HUD（NavigationHUD）

要素	内容
表示情報	ETA / 距離 / 速度 / 方位
スタイル	半透明カード + SF Symbolアイコン
状態	Live Activityにも同期可能

HStack(spacing: 20) {
    Label("ETA 14:35", systemImage: "clock")
    Label("3.2 nm", systemImage: "arrow.up.right.circle")
    Label("12.5 kn", systemImage: "speedometer")
}
.font(.headline)
.foregroundStyle(.white)
.background(.ultraThinMaterial)
.cornerRadius(20)
.shadow(radius: 10)


⸻

3. 潮汐・風速グラフ（Charts）

| フレームワーク | Swift Charts |
| アニメーション | .easeInOut(duration: 1.2) |
| 配色 | linearGradient(colors: [.cyan, .blue]) |

Chart(tideData) {
    LineMark(
        x: .value("Time", $0.time),
        y: .value("Tide", $0.height)
    )
    .interpolationMethod(.catmullRom)
    .foregroundStyle(.linearGradient(colors: [.cyan, .blue], startPoint: .bottom, endPoint: .top))
}
.frame(height: 200)


⸻

4. Parallax背景（海面層）

要素	内容
技術	CoreMotion + rotation3DEffect
効果	傾きに応じて背景がわずかに動く
用途	ホーム画面背景、水面の揺れ表現

Image("ocean_map")
    .resizable()
    .scaledToFill()
    .rotation3DEffect(.degrees(roll * 6), axis: (x: 0, y: 1, z: 0))
    .blur(radius: 8)
    .opacity(0.95)


⸻

5. 緊急通報ボタン（SafetyButton）

要素	内容
ボタン色	.red.gradient
サイズ	frame(width: 120, height: 120)
形状	円形 + グラスシャドウ
効果	長押し時にHaptic + 確認アラート

Button(action: triggerSOS) {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.largeTitle)
        .foregroundStyle(.white)
        .padding()
        .background(.regularMaterial)
        .clipShape(Circle())
        .shadow(radius: 20)
}
.accessibilityLabel("緊急通報（海上保安庁 118）")


⸻

🗺️ 画面構成と構造

1. Home（航行マップ）

項目	内容
背景	Parallax海図 + motion blur
中央	現在位置・航行ルート線
上部HUD	ETA / 距離 / 方位（GlassCard）
下部	潮流・風向カード（Charts）
常駐表示	Live ActivityでETA更新


⸻

2. Destination（目的地設定）

項目	内容
入力欄	音声入力対応TextField（.thinMaterial背景）
候補表示	リストビュー（SF Symbol付き）
ボタン	“ルート生成” ボタン（Aqua Teal）
補助	現在地から自動推定候補表示


⸻

3. Log（クルーズログ）

項目	内容
レイアウト	List + GlassCardスタイル
表示	日付・航行距離・平均速度・天候
操作	タップで詳細マップ表示（モーダル）
背景	.regularMaterialで紙のような質感


⸻

4. Tide & Weather（潮汐・気象）

項目	内容
上部	潮位グラフ（Charts）
中央	風速・風向・波高（アイコン＋数値）
下部	天候サマリー（Cloudy / Clearなど）
背景	.ultraThinMaterial + Blue gradient


⸻

5. Settings（設定・安全）

項目	内容
スイッチ	アラート有効化、音声警告ON/OFF
スライダー	浅瀬警報距離閾値（m単位）
セクション	緊急通報情報、iCloud同期設定
デザイン	.formStyle(.grouped) + ガラス風セクション


⸻

🧭 アニメーション方針

種類	API	使用箇所
波のゆらぎ	phaseAnimator	背景層・グラデーション
ボタンタップ	withAnimation(.spring())	操作フィードバック
HUD更新	withAnimation(.easeInOut(duration: 0.4))	情報変化
画面遷移	.transition(.opacity.combined(with: .scale))	シーン間
起動時	.opacity + .blur	フェードイン演出


⸻

📱 フォントスタイル

用途	フォント	サイズ	備考
タイトル	SF Pro Display Bold	28pt	吹き抜け感を出す
サブタイトル	SF Pro Rounded Medium	20pt	柔らかい印象
本文	SF Pro Text Regular	16pt	読みやすさ重視
情報値	SF Mono	14pt	数値情報の精密感


⸻

🔔 Live Activities（Dynamic Island）

表示要素	内容
ルート名	出発地 → 目的地
ETA	到着予定時刻（リアルタイム更新）
現在速度	kn単位表示
状況	“航行中 / 停泊中 / 到着” などステータス表示


⸻

🧠 インタラクションガイド
	•	長押し操作はすべて Haptic Feedback 対応
	•	状態変化（ETA更新・警告）は subtle なフェードで通知
	•	バイブレーションは警報のみ使用（過剰通知防止）
	•	操作はすべて片手親指操作を想定（iPhone 6.1〜6.7インチ対応）

⸻

🪶 トーン & マナー
	•	画面内に「線」「枠」は極力使わず、光と影で区別
	•	色の強調は Aqua Teal のみを使用（1画面1点）
	•	フラットではなく“浮いている感覚”をデザイン基調に
	•	音・光・動きは“静かな高級感”を維持

⸻

📘 デザイン原則（iOS Human Interface準拠）
	1.	Depth（奥行き） – 要素にレイヤー構造をもたせる
	2.	Clarity（明瞭さ） – 余白とフォント階層で情報を整理
	3.	Vibrancy（透明感） – 背景との対比で視認性を保つ
	4.	Consistency（統一性） – すべての画面で同じGlass体系
	5.	Motion（自然な動き） – 動作に目的をもたせる

⸻

© 2025 Yukihiro / XerographiX

