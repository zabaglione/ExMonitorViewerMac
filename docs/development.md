# 開発者向け情報

## ビルドと起動

Apple Silicon搭載Mac、macOS 26以降、Xcode 26以降を使います。外部ライブラリや追加のMetal Toolchainは不要です。アプリが起動している場合は終了し、リポジトリのルートで実行してください。

```sh
./scripts/build.sh
open dist/ExMonitorViewerMac.app
```

生成先は `dist/ExMonitorViewerMac.app`、ビルドの中間生成先は `build/DerivedData` です。起動には `dist` のアプリを使ってください。ビルドスクリプトは開始時とアプリ置換前に実行中のアプリを検出し、ビルド用コピーを起動候補から外して `dist` を登録します。

標準ではad-hoc署名を使います。配布用のDeveloper ID署名・公証・アップロードは行いません。

## テスト

```sh
./scripts/test.sh
```

幾何計算・設定・フレームの世代管理をホストレスXCTestで確認します。画面収録許可や実際の表示品質は実機で別途確認してください。現在の検証範囲は[検証記録](validation.md)に記載しています。

## 開発中の画面収録許可

ad-hoc署名では、再ビルドによって署名ハッシュが変わります。macOSの設定がONでも、保存済みのコード署名条件と一致せず、画面収録が拒否される場合があります。OFF→ONだけでは直らないこともあります。

その場合はアプリを終了し、システム設定からこのアプリの項目だけを削除して、現在の `dist/ExMonitorViewerMac.app` を新しく追加・許可してください。別の生成先のコピーを同時に起動しないようにします。

既存の開発用証明書を選んで署名する場合は、`EXMONITOR_SIGN_IDENTITY` にその証明書の名前または識別子を明示できます。証明書は自動選択・作成しません。環境固有の証明書名や識別子をリポジトリに保存しないでください。

署名とプライバシー許可の関係は[Appleのコード署名解説](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)を参照してください。

## 配布準備

一般ユーザー向けの配布物は未作成です。公開配布に進む場合は、現在のソースからの再ビルド、Developer ID署名と公証、配布用パッケージ作成、初回インストールと画面収録許可の実機確認を行います。[Appleの配布案内](https://developer.apple.com/developer-id/)も参照してください。

`build/`、`dist/`、ビルドログ、画面画像はGit管理対象外です。
