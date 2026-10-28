#!/usr/bin/env bash
# 設定ファイル(.wp-release)の読み込みと --list のテスト.
# shellcheck disable=SC2329,SC2317  # test_ で始まる関数は、tests_main が名前で呼ぶ(shellcheck には呼び出しが見えない)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

# --- 設定ファイルの探し方 ------------------------------------------------------------------------

test_config_is_found_from_a_subdirectory() {
	mk_docroot found
	mkdir -p deep/er && cd deep/er || return 1
	run_tool --list
	assert_rc 0
	assert_has "my-plugin"
}

test_config_in_a_subdirectory_of_the_git_root() {
	mk_docroot sub app/public
	cd wp-content || return 1
	run_tool --list
	assert_rc 0
	assert_has "$(printf '%s' "${BASE}")/.wp-release"
}

test_outside_a_git_repository_stops() {
	mkdir -p "${TEST_ROOT}/nogit" && cd "${TEST_ROOT}/nogit" || return 1
	run_tool --list
	assert_rc 1
	assert_has "Git リポジトリの中で実行してください"
}

test_missing_config_stops() {
	mkdir -p "${TEST_ROOT}/noconfig" && cd "${TEST_ROOT}/noconfig" && git init -q -b main || return 1
	run_tool --list
	assert_rc 1
	assert_has "設定ファイル .wp-release が見つかりません"
}

# --- 設定の誤り(1 件ずつ、行番号つきまたは理由つきで止まる) ---------------------------------------

# 設定を差し替えて --list を流し、終了コード 1 と、期待する文字列を確かめる. 引数 = 場面・期待する文字列・設定の本文.
expect_config_error() {
	LABEL="$1"
	printf '%s\n' "$3" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 1
	assert_has "$2"
}

test_config_errors_stop_with_a_reason() {
	mk_docroot cfgerr
	expect_config_error "output なし" "output(Zip の出力先)を書いてください" "plugin ${P}"
	expect_config_error "対象なし" "対象(plugin / theme / dir の行)が 1 つもありません" "output = ../r"
	expect_config_error "不明な行" ".wp-release:2: 読めない行です" $'output = ../r\nfoo bar'
	expect_config_error "スラッグ重複" "スラッグ 'same' が重複しています" $'output = ../r\nplugin a/x same\ntheme b/y same'
	expect_config_error "複数なのに {slug} なし" "tag_format には {slug} も含めてください" $'output = ../r\ntag_format = {version}\nplugin a/x\ntheme b/y'
	expect_config_error "{version} なし" "tag_format には {version} を含めてください" $'output = ../r\ntag_format = abc\nplugin a/x'
	expect_config_error "パスに .." "'..' を含まない形" $'output = ../r\nplugin ../x'
	expect_config_error "絶対パス" "相対パスで" $'output = ../r\nplugin /abs/x'
	expect_config_error "パス . でスラッグなし" "スラッグを書いてください" $'output = ../r\nplugin .'
	expect_config_error "requires が新しすぎる" "古すぎます" $'output = ../r\nrequires = 99.0.0\nplugin a/x'
	expect_config_error "requires の形式" "requires は 'X.Y.Z' の形" $'output = ../r\nrequires = 1.2\nplugin a/x'
	expect_config_error "check にコロンなし" "check は 'check <パス>:<正規表現>' の形" $'output = ../r\nplugin a/x\ncheck foo'
	expect_config_error "check の正規表現が空" "check の正規表現が空です" $'output = ../r\nplugin a/x\ncheck a/x/f:'
	expect_config_error "check がどの対象にも属さない" "どの対象のディレクトリの下にもありません" $'output = ../r\nplugin a/x\ncheck elsewhere/x.json:"version"'
	expect_config_error "余分な語" "plugin の行に余分な語があります" $'output = ../r\nplugin a/x slug extra'
	expect_config_error "output が 2 回" "output が 2 回書かれています" $'output = a\noutput = b\nplugin a/x'
	expect_config_error "tag_format が 2 回" "tag_format が 2 回書かれています" $'output = a\ntag_format = {version}\ntag_format = {version}\nplugin a/x'
	expect_config_error "値が空" "output の値が空です" $'output =\nplugin a/x'
	expect_config_error "= が無い" "'output = 値' の形で書いてください" $'output a\nplugin a/x'
	expect_config_error "スラッグの文字" "スラッグ 'bad/slug'" $'output = ../r\nplugin a/x bad/slug'
	expect_config_error "先頭のドットのスラッグ" "スラッグ '.hidden'" $'output = ../r\nplugin a/x .hidden'
}

# 大きさの上限(max_*)の誤り: 正の整数と、末尾の K・M・G だけが書ける. 行番号つきで止まる.
test_size_limit_errors_stop_with_a_reason() {
	mk_docroot limerr
	expect_config_error "0" ".wp-release:2: max_zip_bytes は、正の整数で書いてください" $'output = ../r\nmax_zip_bytes = 0\nplugin a/x'
	expect_config_error "小数" ".wp-release:2: max_files は、正の整数で書いてください" $'output = ../r\nmax_files = 1.5\nplugin a/x'
	expect_config_error "負の数" "max_uncompressed_bytes は、正の整数で書いてください" $'output = ../r\nmax_uncompressed_bytes = -5\nplugin a/x'
	expect_config_error "単位だけ" "max_zip_bytes は、正の整数で書いてください" $'output = ../r\nmax_zip_bytes = M\nplugin a/x'
	expect_config_error "知らない単位" "max_zip_bytes は、正の整数で書いてください" $'output = ../r\nmax_zip_bytes = 20MB\nplugin a/x'
	expect_config_error "桁が多すぎる" "max_zip_bytes は、正の整数で書いてください" $'output = ../r\nmax_zip_bytes = 9999999999999\nplugin a/x'
	expect_config_error "2 回" "max_files が 2 回書かれています" $'output = ../r\nmax_files = 5\nmax_files = 6\nplugin a/x'
	expect_config_error "値が空" "max_files の値が空です" $'output = ../r\nmax_files =\nplugin a/x'
}

# 上限の書き方(正常): 整数・K・M・G(小文字も)・先頭の 0 を含む値. --list も、書き方の誤りがなければ通る.
test_size_limits_are_accepted() {
	mk_docroot limok
	printf 'output = %s\nmax_zip_bytes = 20M\nmax_files = 08\nmax_uncompressed_bytes = 1g  # 末尾のコメント\nplugin %s\n' "${OUTD}" "${P}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "my-plugin"
}

# --- 設定の読み方(正常) --------------------------------------------------------------------------

test_config_comments_and_spacing_are_accepted() {
	mk_docroot cfgok
	printf '# 先頭のコメント\n\noutput=%s   # 末尾のコメント\r\nplugin   %s   # 対象\n' "${OUTD}" "${P}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "my-plugin"
}

test_config_path_notation_is_normalized() {
	mk_docroot cfgpath
	printf 'output = %s\nplugin ./%s/\n' "${OUTD}" "${P}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "1.2.3"
}

test_output_path_with_dotdot_is_shown_normalized() {
	mk_docroot cfgout
	printf 'output = ../releases\nplugin %s\n' "${P}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "出力先:     ${TEST_ROOT}/releases"
}

test_tag_format_defaults_to_version_for_a_single_target() {
	mk_docroot tagdef
	printf 'output = %s\nplugin %s\n' "${OUTD}" "${P}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "タグの形式: {version}"
}

test_tag_format_defaults_to_slug_and_version_for_several_targets() {
	mk_docroot tagdef2
	printf 'output = %s\nplugin %s\ntheme %s\n' "${OUTD}" "${P}" "${TH}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "タグの形式: {slug}/{version}"
}

# --- --list の表示 -------------------------------------------------------------------------------

test_list_shows_versions_and_tag_state() {
	mk_docroot list
	git tag -a my-plugin/1.2.3 -m t
	run_tool --list
	assert_rc 0
	# KIND SLUG VERSION TAG TAGGED PATH の列. プラグインはタグあり(yes)・テーマはタグなし(no).
	printf '%s\n' "${OUT}" | grep -aE '^plugin +my-plugin +1\.2\.3 +my-plugin/1\.2\.3 +yes ' >/dev/null || fail "plugin の行が違います"
	printf '%s\n' "${OUT}" | grep -aE '^theme +my-theme +0\.1\.0 +my-theme/0\.1\.0 +no ' >/dev/null || fail "theme の行が違います"
	printf '%s\n' "${OUT}" | grep -aE '^dir +landing +2\.0\.0 +landing/2\.0\.0 +no ' >/dev/null || fail "dir(スラッグ landing)の行が違います"
	# プラグインの版は、Plugin Name を持つファイル('my main.php')から読む(a-helper.php の 9.9.9 ではない).
	assert_lacks "9.9.9"
}

test_list_marks_missing_directories_and_unreadable_versions() {
	mk_docroot listbad
	mkdir -p novers && printf '<?php\n' > novers/x.php
	printf 'output = %s\nplugin novers np\nplugin missing mm\n' "${OUTD}" > "${BASE}/.wp-release"
	run_tool --list
	assert_rc 0
	assert_has "版を読めません"
	assert_has "ディレクトリがありません"
}

test_list_for_a_single_plugin_with_dot_path() {
	mk_single dot
	run_tool --list
	assert_rc 0
	assert_has "solo-plugin"
	assert_has "0.5.0"
}

tests_main "$@"
