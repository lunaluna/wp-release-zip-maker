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
