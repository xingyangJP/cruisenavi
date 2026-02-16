# RideLane テスト手順
バージョン: 1.0.39  
更新日: 2026-02-15

## 1. 前提
- Xcode 17+
- iOS シミュレータ
- `Config/Weather.plist` 設定済み（詳細は `docs/API.md`）

## 2. ビルド
```bash
cd /Users/xingyang/cruisenavi
xcodebuild -project SeaNavi/RideLane.xcodeproj -scheme SeaNavi -destination 'generic/platform=iOS Simulator' build
```

## 3. 手動確認
1. アプリ起動で Home 表示、右下バージョンが `ver1.0.39` になっている
2. 目的地設定を開き、100km 圏内候補が表示される
3. 候補選択後にプレビュー画面が表示される
4. スタートで Driving へ遷移し、案内カードとズーム UI が表示される
5. 位置情報 OFF 時に追跡状態が「位置情報なし」になる
6. 天気カードに天候・風速（m/s）・風向・路面リスクが表示される
7. 降雨が予測される場合「xx分後に雨が降る見込み」と表示される
8. ナビ終了後、Health 許可ダイアログを許可すると Apple Health にワークアウト（自転車）が追加される

## 4. ログ確認
- ルート失敗時に警告文が表示されること
- API 失敗時に「気象データ更新に失敗」が表示されること
