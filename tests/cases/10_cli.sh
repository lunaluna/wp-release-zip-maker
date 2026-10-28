#!/usr/bin/env bash
# コマンドラインの引数・--help・--version のテスト.
# shellcheck disable=SC2329,SC2317  # test_ で始まる関数は、tests_main が名前で呼ぶ(shellcheck には呼び出しが見えない)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

# ツールの版(ソースの WP_RELEASE_ZIP_MAKER_VERSION の値).
tool_version() {
	sed -n 's/^WP_RELEASE_ZIP_MAKER_VERSION="\(.*\)"$/\1/p' "${TOOL}" | head -n 1
}

test_version_prints_tool_version() {
	run_tool --version
	assert_rc 0
	assert_eq "wp-release-zip-maker $(tool_version)" "${OUT}" "--version の出力"
}

test_help_lists_all_commands() {
	run_tool --help
	assert_rc 0
	assert_has "--dry-run"
	assert_has "--rebuild [<版>]"
	assert_has "--list"
	assert_has "--version"
}

# --verify-content は --dry-run と一緒にだけ使える(単独・--list・--rebuild だけ は使い方の誤り). 説明にも載る.
test_verify_content_needs_dry_run() {
	run_tool --help; assert_has "--verify-content"
	LABEL="単独"; run_tool my-plugin --verify-content; assert_rc 2; assert_has "--verify-content は --dry-run と一緒にだけ"
	LABEL="--rebuild だけ"; run_tool my-plugin --rebuild --verify-content; assert_rc 2; assert_has "--verify-content は --dry-run と一緒にだけ"
	LABEL="--list"; run_tool --list --verify-content; assert_rc 2; assert_has "--list には"
}

# --json は、パスを 1 つ取り、build・--rebuild の成功のあとにだけ使える(--dry-run・--list とは使えない).
test_json_option_usage_errors() {
	run_tool --help; assert_has "--json <パス>"
	LABEL="パスなし"; run_tool my-plugin --json; assert_rc 2; assert_has "--json にはレポートを作るパスを付けてください"
	LABEL="次がオプション"; run_tool my-plugin --json --manifest; assert_rc 2; assert_has "--json にはレポートを作るパスを付けてください"
	LABEL="--dry-run"; run_tool my-plugin --dry-run --json r.json; assert_rc 2; assert_has "--json は --dry-run と一緒に使えません"
	LABEL="--list"; run_tool --list --json r.json; assert_rc 2; assert_has "--list には"
}

test_help_wins_over_other_arguments() {
	run_tool --foo --help
	assert_rc 0
	assert_has "使い方:"
}

test_no_arguments_is_a_usage_error() {
	run_tool
	assert_rc 2
	assert_has "使い方:"
}

test_unknown_option_is_a_usage_error() {
	run_tool --foo
	assert_rc 2
	assert_has "不明なオプション '--foo'"
}

test_third_positional_argument_is_rejected() {
	run_tool my-plugin 1.2.3 extra --rebuild
	assert_rc 2
	assert_has "余分な引数です('extra')"
}

test_version_argument_requires_rebuild() {
	run_tool my-plugin 1.2.3
	assert_rc 2
	assert_has "版を指定できるのは --rebuild のときだけです"
}

test_slug_is_required() {
	run_tool --dry-run
	assert_rc 2
	assert_has "スラッグを指定してください"
}

test_list_rejects_slug_and_other_options() {
	LABEL="スラッグ"; run_tool --list my-plugin; assert_rc 2; assert_has "--list には"
	LABEL="--dry-run"; run_tool --list --dry-run; assert_rc 2; assert_has "--list には"
	LABEL="--rebuild"; run_tool --list --rebuild; assert_rc 2; assert_has "--list には"
}

test_works_through_a_symlink() {
	local link="${TEST_ROOT}/linked-tool"
	ln -s "${TOOL}" "${link}"
	OUT="$("${TOOL_BASH}" "${link}" --version 2>&1)"
	RC=$?
	assert_rc 0
	assert_eq "wp-release-zip-maker $(tool_version)" "${OUT}" "シンボリックリンク経由の --version"
}

tests_main "$@"
