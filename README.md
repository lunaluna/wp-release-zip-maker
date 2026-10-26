# wp-release-zip-maker

GitHub の Release を使えないプロジェクト(クライアントワークなど)でも、テーマ・プラグイン・
WordPress の外のディレクトリの配布用 Zip を、**ローカルで・版を管理しながら**作るコマンドです。

> **開発中(0.1.0)**: 骨組みだけです。`--version` と `--help` 以外はまだ動きません。
> 仕様と進め方は、実装が進むにつれてこの README に書き足します。

## 何をするか(予定)

- サーバーでは Git を使いません。テーマ・プラグインは管理画面の Zip アップロード、ディレクトリは SSH で上げて unzip します
- 1 つのリポジトリにテーマとプラグインなど複数のものが入っていても、それぞれの Zip を作れます
- Zip の作成は WP-CLI の公式パッケージ `wp dist-archive` に任せます。このツールは git と版の管理を担う薄いラッパーです
- 版のタグは素の版番号です(`v` を付けません)

## 必要なもの

- bash(macOS 標準の 3.2 で動く書き方にします)
- git・`zip`
- WP-CLI と、そのパッケージ `wp-cli/dist-archive-command`

`wp dist-archive` の入れ方は、WP-CLI の版によって変わります。

```bash
wp package install wp-cli/dist-archive-command:3.1.0   # WP-CLI 2.12.x
```

版を指定せずに入れると、WP-CLI 2.12.x では失敗します(最新版が WP-CLI 3.0 以上を要求するため)。
WP-CLI 2.13 以上なら、`v3.2.x` も入ります。

## 使い方(予定)

```text
wp-release-zip-maker <slug>              # Zip を作り、タグを打つ(push はしない)
wp-release-zip-maker <slug> --dry-run    # 確認だけ(Zip もタグも作らない)
wp-release-zip-maker <slug> --rebuild    # 既存のタグから Zip を作り直す(タグは打たない)
wp-release-zip-maker --list              # 設定にある対象と、今の版・タグの有無を一覧にする
wp-release-zip-maker --version / --help
```

## ライセンス

GPL-2.0-or-later。全文は [LICENSE](LICENSE) を参照してください。
