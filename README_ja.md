<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語English</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# SwiftClip

SwiftClip は、macOS 26.0 以降を対象とした、ローカルファースト設計の macOS メニューバー用クリップボードマネージャー兼スニペットランチャーです。クリップボードの履歴、再利用可能なスニペット、設定、インポート／エクスポートデータをユーザーの Mac 上に保存し、アクセシビリティ権限を付与することで、選択した履歴またはスニペットを直前にフォーカスしていたアプリへ貼り付けます。

## UI プレビュー

<img src="GitHub Documents/swiftclip-snippet-editor.png" alt="SwiftClip スニペットエディタウィンドウ" width="480">

スニペットエディタは、サイドバーにフォルダとスニペットを整理して表示し、詳細ペインでスニペットの編集、有効／無効の切り替え、ショートカットの記録、大きなコンテンツエディタを利用できます。

## 機能

- アイテム数の上限とタイトルの長さを設定できるメニューバーのクリップボード履歴。
- アイテムごとの有効／無効設定が可能な、再利用可能なスニペットフォルダとスニペットアイテム。
- 設定可能なグローバルショートカットから開く、スタンドアロンの履歴／スニペットポップアップ。
- ドラッグ＆ドロップによるフォルダの並び替え、スニペットの並び替え、フォルダをまたいだスニペットの移動が可能なスニペットエディタ。
- スニペット移行のための Clipy 互換 XML インポート／エクスポート。
- プレーンテキスト、RTF、RTFD、ファイル URL、URL、PDF、画像のフォーマットフィルタリング。
- キャプチャ対象から除外するアプリのバンドル ID 指定。
- 大きなクリップボードデータ向けに、JSON メタデータとは別に BLOB ファイルを保存するローカルストレージ。
- Service Management によるログイン時起動設定。

## 技術スタック

- Swift 6
- SwiftUI および AppKit
- 設定のスキャフォールディングに SwiftData モデル定義を使用し、現在のストアはローカル JSON ファイルで管理
- KeyboardShortcuts 2.4.0 以降の互換リリース
- Xcode プロジェクトベースの macOS アプリビルド

## 動作要件

- macOS 26.0 以降
- Apple Silicon Mac
- Xcode 26.4 以降
- 自動ペースト注入のためのアクセシビリティ権限

## ソースからのビルド

Xcode で `SwiftClip.xcodeproj` を開き、`SwiftClip` スキームをビルドしてください。

コマンドラインによる Debug ビルドの場合：

```sh
xcodebuild -project SwiftClip.xcodeproj \
  -scheme SwiftClip \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/swiftclip-derived \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

ローカルでのビルドおよび起動確認の場合：

```sh
./script/build_and_run.sh --verify
```

## テスト

以下のコマンドでテストスイート全体を実行できます：

```sh
xcodebuild -project SwiftClip.xcodeproj \
  -scheme SwiftClip \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/swiftclip-derived \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

テストは、BLOB ストレージ、Clipy XML インポート／エクスポート、履歴の永続化、メニュータイトルのフォーマット、設定の永続化、スニペットの並び替え動作をカバーしています。

## 使い方

1. SwiftClip を起動します。
2. 直前にフォーカスしていたアプリへ選択したアイテムを貼り付ける場合は、プロンプトが表示されたらアクセシビリティ権限を許可してください。
3. メニューバーアイテムを使って、クリップボード履歴、スニペット、設定、アプリアクションを確認できます。
4. 設定でショートカットを設定します。
5. スニペットエディタを開いて、フォルダの作成、スニペットの編集、スニペットショートカットの割り当て、Clipy XML のインポート、または SwiftClip スニペットのエクスポートを行います。

## ローカルデータ

SwiftClip のアプリデータは以下に保存されます：

```text
~/Library/Application Support/SwiftClip
```

クリップボードの BLOB は JSON 履歴インデックスとは別に保存されるため、大きなバイナリデータがメタデータファイルを肥大化させることはありません。

## プロジェクト構成

```text
SwiftClip/
  App/              アプリのライフサイクルと環境の配線
  Clipboard/        クリップボードのキャプチャ、履歴、BLOB ストレージ、ペーストサポート
  MenuBar/          メニューバーおよびスタンドアロンポップアップメニューのビルダー
  Onboarding/       権限リクエスト UI
  Preferences/      設定ストアと設定タブ
  SnippetEditor/    スニペットエディタウィンドウ、アウトライン、ツールバー、詳細ペイン
  Snippets/         スニペットモデル、ストア、Clipy XML コーデック
  Support/          共有ロギング、ローカライゼーション、エラー、ファイルパス
SwiftClipTests/     永続化、メニュー、BLOB、XML、順序の XCTest カバレッジ
script/             ローカルビルドおよび起動ヘルパー
```

## トラブルシューティング

- パッケージの解決に失敗した場合は、Xcode で `SwiftClip.xcodeproj` を開いてパッケージを解決するか、ネットワーク接続がある状態で `xcodebuild -list -project SwiftClip.xcodeproj` を再実行してください。
- 自動ペーストが機能しない場合は、システム設定のアクセシビリティで SwiftClip が許可されているか確認してください。
- Xcode の警告 `Metadata extraction skipped. No AppIntents.framework dependency found.` は、このプロジェクトで既知の警告であり、ビルドの失敗ではありません。

## ライセンス

MIT。`LICENSE` を参照してください。