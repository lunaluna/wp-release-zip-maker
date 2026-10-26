# Changelog

このファイルは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式に従います。
版は素の版番号です(`v` を付けません)。

## [Unreleased]

### Added

- `bin/wp-release-zip-maker` の骨組み(`--version`・`--help`・引数の解釈)
- README・CHANGELOG・LICENSE(GPL-2.0-or-later)
- 設定ファイル `.wp-release` の読み込み(Git のルートまで上へ探す・形式の誤りは行番号つきで止める・`requires` でツールの版を確かめる)
- `--list`(対象ごとの版・タグの有無)。版は theme = `style.css`・plugin = `Plugin Name:` を持つ直下の php・dir = `VERSION` から読む
- 設定の見本 `examples/`(docroot 型・プラグイン 1 つ型)
- 事前の確認と `--dry-run`: 道具(zip・WP-CLI・wp dist-archive)・コミットの有無・対象と `.distignore`・作業ツリー・版と `check`・タグ・出力先の Zip を確かめ、止める条件に当てはまれば理由つきで止める
- `check` は、そのパスを含む対象にだけ適用する(どの対象の下にもない `check` は設定の誤りとして止める)
- 環境変数 `WP_RELEASE_ZIP_MAKER_WP`(使う WP-CLI の指定)
- 設定のパスの表記ゆれ(先頭の `./`・末尾の `/`)をそろえる
- Zip の作成: `git archive` で HEAD の対象を一時ディレクトリの `<slug>/` へ展開し、`wp dist-archive` で Zip にする. 一番上のフォルダーはスラッグ. 作った Zip の中身(すべて `<slug>/` の下)を確かめ、サイズ・SHA-256・ファイル数・直下の内訳を表示する
- 失敗したとき(wp の失敗・Zip の構造が不正)は、作りかけの Zip を消す. 一時ディレクトリは終了時・Ctrl-C のときも消す
- 注釈付きタグ: Zip を作れたら HEAD にタグを打つ(push はしない). メッセージに Zip の名前・SHA-256・内容の指紋(Content-SHA-256)・ツールの版を記録する. タグを打てなければ Zip も消す. 打つ前にコミッターの名前・メールを確かめる
- `--rebuild [<版>]`: 既存のタグの時点から Zip だけを作り直す(タグは打たない・作業ツリーの状態は問わない・Zip の上書きはしない). 版を省くと HEAD の版. 作り直した Zip の内容の指紋を、タグの記録と比べて表示する. `--dry-run` と組み合わせられる
- 版・`.distignore`・`check` は、作業ツリーではなく ref(HEAD・タグ)の内容から読む. `--rebuild` は「タグの時点」で確かめ、タグ名の版と食い違えば止める
- 警告: Zip に設定ファイル `.wp-release` が入っているとき / ASCII 以外のファイル名があるとき(macOS・Linux の `zip` は「UTF-8 の名前」の印を付けないため)
