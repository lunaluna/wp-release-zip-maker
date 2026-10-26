# wp-release-zip-maker

GitHub の Release を使えないプロジェクト(クライアントワークなど)でも、テーマ・プラグイン・
WordPress の外のディレクトリの配布用 Zip を、**ローカルで・版を管理しながら**作るコマンドです。

> **開発中(0.1.0)**: `--version`・`--help`・`--list`・`--dry-run`(事前の確認)・Zip の作成が動きます。
> タグ付け・`--rebuild`・`dir` のアップロード手順の表示は、まだありません。
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

- `#` で始まる行と、空白の後ろの `#` 以降はコメントです(`check` の正規表現には、空白のあとに `#` を続けて書けません)
- パスは設定ファイルからの相対パスです。絶対パスと `..` は使えません。パス `.` はスラッグの省略ができません
- スラッグは英数字・ドット・ハイフン・アンダースコアだけです(先頭のドットは不可)。対象どうしで重複できません
- 対象が複数あるときは、`tag_format` に `{slug}` を含めます(別の対象のタグが衝突するため)
- `output` は省略できません(省略時の置き場所を決めると、Git の中に Zip を作る事故につながるため)
- `check` は、そのパスを含む対象(`plugin`/`theme`/`dir` のディレクトリの下)の確認にだけ使います。
  たとえばプラグインとテーマの両方が入る設定で、プラグインの Zip を作るときに、テーマの `package.json` とは比べません。
  どの対象の下にもない `check` は、書き間違いとして止めます

### 事前の確認(`<slug> --dry-run`)

Zip もタグも作らずに、止めるべき状態がないかを確かめます。通常の実行(`<slug>`)も、同じ確認を先に行います。
次の順に確かめて、1 つでも当てはまれば止めます(終了コード 1)。

| 確かめること | 止める条件 |
| --- | --- |
| 設定 | スラッグが設定にない / `requires` よりツールが古い |
| 道具 | `zip` コマンド・WP-CLI・`wp dist-archive` のどれかがない(入れ方を表示) |
| コミット | リポジトリにコミットがない(Zip は HEAD から作る) |
| 対象 | ディレクトリがない / コミット済みの `.distignore` がない |
| 作業ツリー | 未コミット・未追跡の変更がある |
| 版 | 版を読むファイルが Git に入っていない / 版を読めない / 版がタグ名に使えない形(英数字で始まり、英数字と `. _ + -` だけ) |
| `check` | 食い違いがある(**すべて表示してから止める**。版の前後は英数字・`. _ + -` 以外であること: `1.2.3` は `11.2.30` や `1.2.3-beta` に一致しない) |
| タグ | すでにある(`--rebuild` か版を上げる) |
| 出力先の Zip | すでにある(タグがあれば「消してから `--rebuild`」、タグがなければ「作りかけの Zip が残っている」) |

止めずに警告だけ出すもの: ブランチが `main`/`master` でない・detached HEAD・出力先が Git の中で `.gitignore` にも入っていない。

`.distignore` が必須なのは、`wp dist-archive` が `.distignore` なしだと、`node_modules` や `src` を含む全ファイルを Zip に入れてしまうためです。

`WP_RELEASE_ZIP_MAKER_WP` に WP-CLI のパスを入れると、PATH 上の `wp` の代わりにそれを使います(複数の `wp` がある場合)。

### Zip の作り方(`<slug>`)

事前の確認が通ると、**HEAD の内容から**Zip を作ります(作業ツリーは使いません)。

1. `git archive` で、対象のディレクトリを一時ディレクトリの `<slug>/` へ展開します(未追跡・`.gitignore` で無視されたファイルは入りません)
2. `wp dist-archive` が、`.distignore` を適用して Zip にします。Zip の一番上のフォルダーはスラッグです
   (WordPress の管理画面からの上書きは、この名前で既存のものを置き換えるため)
3. 作った Zip の中身を確かめます(すべてが `<slug>/` の下にあること)。失敗したときは、作りかけの Zip を消します
4. サイズ・SHA-256・ファイル数・直下の内訳を表示します

出力先のディレクトリが無ければ作ります。Zip の名前は `<出力先>/<slug>.<版>.zip` です。

知っておくこと:

- **`.gitattributes` の `export-ignore` が効きます。** `git archive` の仕様で、`.distignore` に書かなくても、それに合うファイルは Zip に入りません
- **設定ファイルが Git のルートの下にあっても動きます**(たとえば `app/public/.wp-release`。パスはそこからの相対パスで書きます)
- **プラグイン 1 つ型(パス `.`)では、`.wp-release` が対象の中に入ります。** `.distignore` に `.wp-release` と `.distignore` を書いてください(入っていると警告します)
- **ASCII 以外(日本語など)のファイル名がある場合は、警告します。** `zip` コマンドが「UTF-8 の名前」の印を付けないため、展開する環境によっては文字化けします。
  テーマ・プラグインのファイル名は英数字にするのが無難です
- `.distignore` の `**/*.log` は、ルート直下の `a.log` に当たりません(深い階層にだけ効きます)。ルート直下も除くなら `*.log` と書きます
- 表示される内訳は、ASCII 以外のファイル名を `?` にして出します(macOS の `unzip` の出力が、そのバイトを落とすため)

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
