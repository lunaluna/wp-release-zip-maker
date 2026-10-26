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
