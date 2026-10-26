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
