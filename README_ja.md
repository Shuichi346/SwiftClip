<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# SwiftClip

SwiftClip は、Clipy の UI と使いやすさにインスパイアされた、macOS 26.0 以降向けのローカルファーストな macOS メニューバー クリップボードマネージャー兼スニペットランチャーです。クリップボードの履歴、再利用可能なスニペット、スニペットの添付ファイル、設定、インポート/エクスポートデータをユーザーの Mac 上に保管し、アクセシビリティ権限が付与されると、選択した履歴またはスニペットアイテムを直前にフォーカスされていたアプリにペーストします。Swift 6、SwiftUI、AppKit で構築されており、Clipy 互換の XML インポート/エクスポート、グローバルショートカット、アプリごとのキャプチャルール、テキストと添付ファイルを混在させたスニペットのペーストをサポートしています。

## 目次

- [UI プレビュー](#ui-preview)
- [機能](#features)
- [技術スタック](#tech-stack)
- [動作要件](#requirements)
- [ソースからビルド](#build-from-source)
- [テスト](#testing)
- [使い方](#usage)
- [設定](#preferences)
- [ローカルデータ](#local-data)
- [プロジェクト構成](#project-structure)
- [トラブルシューティング](#troubleshooting)
- [ライセンス](#license)

## UI プレビュー

<img src="GitHub Documents/swiftclip-snippet-editor.png" alt="SwiftClip スニペットエディタウィンドウ" width="480">

スニペットエディタは、サイドバーにフォルダとスニペットを整理して表示し、詳細ペインには編集可能なスニペットの詳細、有効/無効の切り替え、ショートカットの記録、大きなコンテンツエディタが配置されています。

## 機能

- 設定可能なアイテム数制限とタイトル文字数を持つメニューバークリップボード履歴。
- アイテムごとの有効/無効切り替えが可能な、再利用可能なスニペットフォルダとスニペットアイテム。
- 設定可能なグローバルショートカットから開くスタンドアロンの履歴/スニペットポップアップ。
- ドラッグ＆ドロップによるフォルダの並べ替え、スニペットの並べ替え、フォルダをまたいだスニペットの移動が可能なスニペットエディタ。
- ローカルファイル、画像、動画に対するスニペット添付ファイルのサポート（オプションのプロンプトテキスト付き）。
- 選択したアプリに対して、テキストを先にペーストし、添付ファイルを後でペーストできる混在スニペットペーストのサポート。
- スニペット移行のための Clipy 互換 XML インポートおよびエクスポート。
- プレーンテキスト、RTF、RTFD、ファイル URL、URL、PDF、画像のフォーマットフィルタリング。
- 標準アプリピッカーで選択できる、キャプチャから除外するアプリと混在スニペットペーストアプリのアプリごとの設定。
- 大きなクリップボードペイロード用に個別の Blob ファイルを使用したローカル JSON メタデータストレージ。
- Service Management を利用したログイン時起動設定。

## 技術スタック

- Swift 6
- SwiftUI および AppKit
- 設定のスキャフォールディング用 SwiftData モデル定義（現在のストアはローカル JSON ファイルを使用）
- KeyboardShortcuts 2.4.0 以降の互換リリース
- Xcode プロジェクトベースの macOS アプリビルド

## 動作要件

- macOS 26.0 以降
- Apple Silicon Mac
- Xcode 26.4 以降
- 自動ペースト挿入のためのアクセシビリティ権限

## ソースからビルド

Xcode で `SwiftClip.xcodeproj` を開き、`SwiftClip` スキームをビルドします。

コマンドラインでの Debug ビルド:

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

ローカルでのビルドと起動確認:

```sh
./script/build_and_run.sh --verify
```

## テスト

以下のコマンドでテストスイート全体を実行します:

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

テストは、Blob ストレージ、Clipy XML インポート/エクスポート、履歴の永続化、メニュータイトルのフォーマット、設定の永続化、スニペットの並べ替え動作をカバーしています。

## 使い方

1. SwiftClip を起動します。
2. SwiftClip が直前にフォーカスされていたアプリに選択したアイテムをペーストできるようにするため、プロンプトが表示されたらアクセシビリティ権限を付与します。
3. メニューバーアイテムを使用して、クリップボード履歴、スニペット、設定、アプリのアクションを参照します。
4. 設定でショートカットを設定します。
5. スニペットエディタを開いて、フォルダの作成、スニペットの編集、ファイルの添付、スニペットショートカットの割り当て、Clipy XML のインポート、または SwiftClip スニペットのエクスポートを行います。

## 設定

SwiftClip の設定はローカルに JSON として保存され、メニューバーアプリから利用できます。

- **一般**: ログイン時起動、および履歴アイテムまたはスニペットを選択した後の自動ペースト。
- **メニュー**: 番号表示とメニュータイトルの文字数。
- **フォーマット**: SwiftClip が履歴として記録するペーストボードのフォーマット。
- **アプリ**: クリップボードキャプチャから除外するアプリ、および混在スニペットを「テキスト先、添付ファイル後」の2回のペースト操作として受け取るべきアプリの **混在スニペットペーストアプリ** 設定。
- **ショートカット**: メインポップアップ、スニペットエディタ、設定、履歴クリアアクション用のグローバルショートカット。
- **拡張**: プレーンテキストペースト、選択時削除、ペースト後削除などの修飾キートリガーによるペースト動作。

アプリリストは内部的にバンドル識別子を保存しますが、設定 UI はインストール済みアプリを解決し、わかりやすく `Firefox.app` などの名前を表示します。アプリを解決できない場合、SwiftClip はバンドル ID を表示します。

## ローカルデータ

SwiftClip はアプリデータを以下の場所に保存します:

```text
~/Library/Application Support/SwiftClip
```

クリップボードの Blob は JSON 履歴インデックスとは別に保存されるため、大きなバイナリペイロードがメタデータファイルを肥大化させることはありません。

現在のローカルファイル:

- `Preferences.json`
- `History.json`
- `Snippets.json`
- `Blobs/`

## プロジェクト構成

```text
SwiftClip/
  App/              アプリのライフサイクルと環境の配線
  Clipboard/        クリップボードのキャプチャ、履歴、Blob ストレージ、ペーストサポート
  MenuBar/          メニューバーおよびスタンドアロンポップアップメニューのビルダー
  Onboarding/       権限プロンプト UI
  Preferences/      設定ストアと設定タブ
  SnippetEditor/    スニペットエディタウィンドウ、アウトライン、ツールバー、詳細ペイン
  Snippets/         スニペットモデル、ストア、Clipy XML コーデック
  Support/          共有ロギング、ローカライズ、エラー、ファイルパス
SwiftClipTests/     永続化、メニュー、Blob、XML、並べ替えの XCTest カバレッジ
script/             ローカルビルドおよび起動ヘルパー
```

## トラブルシューティング

- パッケージの解決に失敗した場合は、Xcode で `SwiftClip.xcodeproj` を開いてパッケージを解決するか、ネットワークアクセスがある状態で `xcodebuild -list -project SwiftClip.xcodeproj` を再実行してください。
- 自動ペーストが機能しない場合は、システム設定のアクセシビリティで SwiftClip が承認されていることを確認してください。
- テキストと添付ファイルを混在させたスニペットが、チャットやアップロードフィールドで一部しかペーストされない場合は、そのアプリを **設定 → アプリ → 混在スニペットペーストアプリ** に追加してください。
- Xcode の警告 `Metadata extraction skipped. No AppIntents.framework dependency found.` はこのプロジェクトで既知の警告であり、ビルドの失敗ではありません。

## ライセンス

MIT。`LICENSE` を参照してください。