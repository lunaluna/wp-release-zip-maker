# wp-release-zip-maker

GitHub の Release を使えないプロジェクト(クライアントワークなど)でも、テーマ・プラグイン・
WordPress の外のディレクトリの配布用 Zip を、**ローカルで・版を管理しながら**作るコマンドです。

> **開発中(0.1.0)**: `--version`・`--help`・`--list` だけ動きます。Zip を作る処理はまだありません。
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

## 設定ファイル `.wp-release`

カレントディレクトリから上へ探します(Git のルートで止めます)。Git の外では動きません。
見本は [examples/](examples/) にあります(docroot 型・プラグイン 1 つ型)。

```text
tag_format = {slug}/{version}        # 省略可。対象が 1 つなら {version}、複数なら {slug}/{version}
output     = ../releases             # 必須。設定ファイルからの相対パス。Git と docroot の外を推奨
requires   = 0.1.0                   # 省略可。このツールの最低の版。古ければ止める

# 種類    パス(設定ファイルからの相対)    スラッグ(省略時はディレクトリ名)
plugin   wp-content/plugins/my-plugin
theme    wp-content/themes/my-theme
dir      lp                              landing

# 版の表記がそろっているかの追加の確認(任意)。check パス:正規表現
check    wp-content/plugins/my-plugin/package.json:"version"
```

- `#` で始まる行と、空白の後ろの `#` 以降はコメントです(`check` の正規表現に ` #` は書けません)
- パスは設定ファイルからの相対パスです。絶対パスと `..` は使えません。パス `.` はスラッグの省略ができません
- スラッグは英数字・ドット・ハイフン・アンダースコアだけです(先頭のドットは不可)。対象どうしで重複できません
- 対象が複数あるときは、`tag_format` に `{slug}` を含めます(別の対象のタグが衝突するため)
- `output` は省略できません(省略時の置き場所を決めると、Git の中に Zip を作る事故につながるため)

### 版の読み方

| 種類 | 版を読む場所 |
| --- | --- |
| `theme` | `style.css` の `Version:`(先頭 5000 バイト) |
| `plugin` | 直下の `*.php` のうち `Plugin Name:` を持つ最初のファイル(名前順)の `Version:`(先頭 8192 バイト) |
| `dir` | `VERSION` ファイルの 1 行目 |

### `--list`

設定にある対象と、今の版(作業ツリーのファイル)・タグの有無を一覧にします。

```text
KIND    SLUG        VERSION    TAG                 TAGGED PATH
plugin  my-plugin   1.2.3      my-plugin/1.2.3     yes    wp-content/plugins/my-plugin
theme   my-theme    0.1.0      my-theme/0.1.0      no     wp-content/themes/my-theme
dir     landing     2.0.0      landing/2.0.0       no     lp
```

ディレクトリが無い・版を読めない対象は、`?` を付けて一覧に残します(終了コードは 0)。
設定の形式の誤りは、行番号つきで止めます(終了コード 1)。

## ライセンス

GPL-2.0-or-later。全文は [LICENSE](LICENSE) を参照してください。
