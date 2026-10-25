# ExMonitorViewerMac

Mac の画面を別ウィンドウに表示する、Apple silicon 向け macOS アプリです。

## 要件

- Apple silicon 搭載 Mac、macOS 26 以降（実機確認: macOS 26.6.2）
- 初回利用前に、システム設定の「プライバシーとセキュリティ」で画面収録を許可してください。
- 外部ディスプレイは任意です。キャプチャではアプリ自身の表示ウィンドウを除外します。

## ビルド、起動、テスト

Xcode 26 以降を使い、リポジトリのルートで実行します。

```sh
./scripts/build.sh
open dist/ExMonitorViewerMac.app
./scripts/test.sh
```

ビルド成果物は `dist/ExMonitorViewerMac.app` に作成されます。標準のローカルビルドはアドホック署名で、公証は行いません。配布用バイナリは含まれていません。

## 操作

- `Display` から表示元ディスプレイを選択します。
- `Capture > 30 FPS`、`60 FPS`、`System Maximum` でキャプチャ速度を選びます。`Show Cursor` でカーソル表示を切り替え、`Retry Capture`（⌘R）でキャプチャを再試行します。
- `View > Scale` で `50%`、`100%`、`200%` を選びます。`100%` は映像の1ピクセルを表示先の1バッキングピクセルに対応させます。
- `View > Fit Window to Image`（⌘F）でウィンドウを映像サイズに合わせます。ウィンドウは画面内に収まる大きさに制限されます。
- `View > Always on Top` で最前面表示を切り替えます。`View > Enter Full Screen`（⌃⌘F）でフルスクリーンにします。

このアプリは映像表示専用です。入力操作の転送や音声の録音は行いません。

## 許可済みなのに画面を取得できない場合

開発用のad-hoc署名では、再ビルドでアプリの署名が変わります。macOSの画面収録設定がONでも、以前のビルドに対する許可と一致しなくなる場合があります。

1. ExMonitorViewerMacを終了します。起動には `dist/ExMonitorViewerMac.app` だけを使ってください。
2. システム設定の画面収録で、このアプリの項目だけを削除します。
3. 追加ボタンから現在の `dist/ExMonitorViewerMac.app` を選び、許可します。
4. 同じアプリを開き直し、必要なら `Capture > Retry Capture` を選びます。

ほかのアプリの許可は変更しません。ビルドスクリプトは実行中のアプリを検出すると停止し、ビルド用コピーではなく `dist` を起動先として登録します。

既存の開発用証明書を選んで署名する場合は、`EXMONITOR_SIGN_IDENTITY` にその証明書の名前または識別子を明示できます。証明書の作成、公証、アップロードはスクリプトでは行いません。
