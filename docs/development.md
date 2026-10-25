# 開発者向け情報

## ビルドと起動

Apple Silicon搭載Mac、macOS 26以降、Xcode 26以降を使います。更新機能にSparkle 2.10.0をSwift Package Managerで固定して利用します。初回は依存取得にネット接続が必要です。追加のMetal Toolchainは不要です。

アプリを終了して、リポジトリのルートで実行します。

```sh
./scripts/build.sh
open dist/ExMonitorViewerMac.app
./scripts/test.sh
```

既定はローカル開発用のad-hoc署名・Debugビルドです。Debugでは、Sparkleを読み込めるようHardened Runtimeを無効にしています。ReleaseはHardened Runtimeを有効にし、配布用の例外entitlementは追加しません。

`EXMONITOR_SIGN_IDENTITY`に既存の署名証明書名または識別子を指定するとReleaseビルドになります。スクリプトは署名証明書を自動選択・作成せず、公証・公開も行いません。配布版には以下のArchive→Distribute経路を使ってください。

生成先は`dist/ExMonitorViewerMac.app`、中間生成先は`build/DerivedData`、依存は`build/SourcePackages`です。スクリプトは起動中のアプリを検出すると停止し、生成後は`dist`を起動先に登録します。テストは実際の共有ソースを使うホストレスXCTestで、画面収録や表示品質は別途実機確認します。

## 開発中の画面収録許可

ad-hoc署名では再ビルドで署名ハッシュが変わり、macOSの設定がONでも取得が拒否されることがあります。アプリを終了し、画面収録設定からこのアプリの項目だけを削除して、現在の`dist`アプリを追加・許可してください。複数コピーを同時に起動しないでください。

継続した証明書・bundle IDで署名した配布版では署名要件を維持します。[Appleのコード署名解説](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)も参照してください。

## アイコン

`Resources/AppIcon.icns`は本プロジェクトのCoreGraphics描画コードで生成したオリジナル素材です。

```sh
./scripts/generate-icon.sh
```

編集元は`scripts/generate-icon.swift`、中間PNGは`build/iconset/`です。追加の生成サービスや外部素材は使いません。

## 配布アプリとDMG

1. Releaseのバージョンを設定します。`MARKETING_VERSION`は表示用、`CURRENT_PROJECT_VERSION`は更新判定用の単調増加整数です。最低OSは26.0です。
2. XcodeでProduct → Archiveし、OrganizerのDirect Distributionで既存Developer IDを選びます。Sparkleの補助プロセスも配布用に署名するため、単純なbuild成果物の公開は避けてください。自動化する場合もarchive→exportArchiveを使います。
3. Appleの公証が受理された後、Export Notarized Appで書き出します。`codesign --verify --deep --strict`、`xcrun stapler validate`、`spctl --assess --type execute --verbose=2`で確認します。
4. `./scripts/package-dmg.sh <書き出したExMonitorViewerMac.app>`で、Applicationsリンク付きの`dist/ExMonitorViewerMac.dmg`を生成します。入力アプリの署名・チケット・Gatekeeperを検査します。
5. 最終DMGもDeveloper IDで署名します。DMGコンテナ自体の公証・stapleは別の処理です。このスクリプトは公証を実行しません。
6. 実際のダウンロード、マウント、Applicationsへのコピー、初回起動を確認します。macOSの保護機能を無効にして合格扱いにしないでください。

[Appleの配布案内](https://developer.apple.com/developer-id/)と[Sparkleの配布手順](https://sparkle-project.org/documentation/)を参照してください。

## 更新の配信

本番はHTTPSの`SUFeedURL`を使い、署名済みフィードと更新アーカイブを検証します。インストールの自動実行は禁止し、Sparkleの標準UIで毎回ユーザーに確認します。自動確認の設定はSparkleが保存し、初期確認は通常2回目の起動時です。

更新用Ed25519秘密鍵はこのMacのログインキーチェーンのaccount `ExMonitorViewerMac`に保存します。Gitに含むのはInfo.plistの公開鍵だけです。鍵の生成は初回設定だけで行い、ビルドや配信スクリプトで自動再生成・秘密鍵のファイル出力は行いません。紛失・Mac移行に備えた鍵の管理は開発者が行ってください。

署名・公証・内容確定を終えた最終DMGを専用ディレクトリに置きます。

```sh
./scripts/generate-appcast.sh dist/releases https://example.com/releases/
```

固定バージョンのSparkle公式ツールを使い、キーチェーンの公開鍵がInfo.plistと一致するか確認してからappcastを生成・検証します。URL例は実際の配信先へ置き換えてください。署名後にDMGやXMLを変更すると再署名が必要です。DMGを先に配置してからフィードを更新します。このスクリプトはアップロードしません。

本番URLは公開リポジトリmainブランチの`appcast.xml`です。DMGはGitHub Releasesへ配置します。GitHubトークンをアプリに埋め込みません。次の配信では新しいDMGを公開した後、生成した署名済み`appcast.xml`をルートへそのままコピーしてcommit・pushし、匿名での取得と更新確認を検証してください。XMLを整形・追記すると署名が変わるため、その場合は再署名が必要です。

`UPDATER_TESTING`は隔離した`.UpdateTest` bundle IDだけのローカル試験に使用します。HTTP例外はループバックのみで、通常の配布構成ではコンパイルしません。試験では別名アプリを使い、本体や画面収録許可を変更しません。

Sparkleのライセンスは`Resources/Sparkle-LICENSE.txt`に含め、アプリメニューのThird-Party Licensesから開けます。

`build/`、`dist/`、ローカル検証ログ・データはGit管理対象外です。現在の検証範囲は[検証記録](validation.md)を参照してください。
