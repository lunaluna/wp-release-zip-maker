#!/usr/bin/env bash
# Zip の作成のテスト(実物の `wp dist-archive` と zip・unzip が要る. 無ければ SKIP).
# shellcheck disable=SC2329,SC2317  # test_ で始まる関数は、tests_main が名前で呼ぶ(shellcheck には呼び出しが見えない)
# shellcheck disable=SC2016  # 偽の wp のコードは、展開せずに(偽の wp のスクリプトの中で)評価するので、シングルクォートで渡す
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

# 実物の wp dist-archive が無ければ、このテストを飛ばす. 使い方: need_real_wp || return 0
need_real_wp() {
	if have_dist_archive; then
		return 0
	fi
	skip "実物の wp dist-archive・zip・unzip が無い"
	return 1
}

# Zip のファイル名一覧から、一番上のフォルダー名だけを重複なしで出す.
top_folders() {
	zip_names "$1" | sed 's#/.*##' | LC_ALL=C sort -u | tr '\n' ' '
}

test_plugin_zip_has_the_right_files_and_top_folder() {
	need_real_wp || return 0
	mk_docroot z1
	# .gitignore 済みのファイル(Zip に入ってはいけない)
	mkdir -p "${P}/node_modules/x" && echo 1 > "${P}/node_modules/x/i.js" && echo 1 > "${P}/local.txt"
	run_tool my-plugin
	assert_rc 0
	local z="${OUTD}/my-plugin.1.2.3.zip"
	assert_file "${z}"
	assert_eq "my-plugin " "$(top_folders "${z}")" "一番上のフォルダー"
	zip_has "${z}" "my-plugin/my main.php" || fail "my main.php(空白入りの名前)が入っていません"
	zip_has "${z}" "my-plugin/a-helper.php" || fail "a-helper.php が入っていません"
	zip_has "${z}" "my-plugin/assets/app.js" || fail "assets/app.js が入っていません"
	local excluded
	for excluded in "my-plugin/src/a.js" "my-plugin/package.json" "my-plugin/.distignore" "my-plugin/local.txt" "my-plugin/node_modules/x/i.js"; do
		if zip_has "${z}" "${excluded}"; then fail "入ってはいけないファイルが入っています: ${excluded}"; fi
	done
	assert_has "SHA-256:"
	assert_has "my-plugin/ の直下(ファイル数 名前):"
	assert_eq "0" "$(leftover_tmp_count)" "取り残された一時ディレクトリの数"
}

test_theme_and_dir_zips() {
	need_real_wp || return 0
	mk_docroot z2
	LABEL="theme"; run_tool my-theme; assert_rc 0
	zip_has "${OUTD}/my-theme.0.1.0.zip" "my-theme/style.css" || fail "style.css が入っていません"
	if zip_has "${OUTD}/my-theme.0.1.0.zip" "my-theme/package.json"; then fail "package.json が入っています"; fi
	LABEL="dir(スラッグ landing)"; run_tool landing; assert_rc 0
	assert_eq "landing " "$(top_folders "${OUTD}/landing.2.0.0.zip")" "一番上のフォルダー(ディレクトリ名 lp ではなくスラッグ)"
	zip_has "${OUTD}/landing.2.0.0.zip" "landing/VERSION" || fail "VERSION が入っていません"
	zip_has "${OUTD}/landing.2.0.0.zip" "landing/index.html" || fail "index.html が入っていません"
}

test_export_ignore_attribute_is_honored() {
	need_real_wp || return 0
	mk_docroot z3
	echo 1 > "${P}/export.txt"
	printf 'export.txt export-ignore\n' > "${P}/.gitattributes"
	gcommit "export-ignore"
	run_tool my-plugin
	assert_rc 0
	if zip_has "${OUTD}/my-plugin.1.2.3.zip" "my-plugin/export.txt"; then fail "export-ignore のファイルが入っています"; fi
}

test_output_directory_is_created() {
	need_real_wp || return 0
	mk_docroot z4
	set_config "output = ${OUTD}/a/b
plugin ${P}"
	run_tool my-plugin
	assert_rc 0
	assert_file "${OUTD}/a/b/my-plugin.1.2.3.zip"
}

test_config_inside_a_subdirectory_of_the_git_root() {
	need_real_wp || return 0
	mk_docroot z5 app/public
	run_tool my-theme
	assert_rc 0
	zip_has "${OUTD}/my-theme.0.1.0.zip" "my-theme/style.css" || fail "style.css が入っていません(サブディレクトリ構成)"
	assert_eq "my-theme/0.1.0" "$(git tag)" "打たれたタグ"
}

test_single_plugin_with_dot_path() {
	need_real_wp || return 0
	mk_single z6
	LABEL="Git のルート"; run_tool solo-plugin; assert_rc 0
	assert_eq "solo-plugin/inc.php solo-plugin/solo-main.php" "$(zip_names "${OUTD}/solo-plugin.0.5.0.zip" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "Zip の中身(Git のルート)"
	mk_single z6b sub/dir
	LABEL="サブディレクトリ"; run_tool solo-plugin; assert_rc 0
	assert_eq "solo-plugin/inc.php solo-plugin/solo-main.php" "$(zip_names "${OUTD}/solo-plugin.0.5.0.zip" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "Zip の中身(サブディレクトリ)"
}

test_non_ascii_file_names_warn_but_do_not_break_the_summary() {
	need_real_wp || return 0
	mk_docroot z7
	echo 1 > "${TH}/日本語.txt"
	gcommit "non-ascii name"
	run_tool my-theme
	assert_rc 0
	assert_has "ASCII 以外の文字を含むファイル名が 1 個あります"
	assert_has "my-theme/ の直下(ファイル数 名前):"
}

test_config_file_inside_the_zip_warns() {
	need_real_wp || return 0
	mk_single z8
	printf '.distignore\n' > .distignore   # .wp-release を書き忘れた状態
	gcommit "forgot .wp-release"
	run_tool solo-plugin
	assert_rc 0
	assert_has "solo-plugin/.wp-release(このツールの設定)が入っています"
}

test_second_run_stops_because_tag_and_zip_exist() {
	need_real_wp || return 0
	mk_docroot z9
	run_tool my-plugin; assert_rc 0
	run_tool my-plugin
	assert_rc 1
	assert_has "タグ my-plugin/1.2.3 も Zip もすでにあります"
}

# 失敗したとき(wp が失敗・Zip の構造が不正)は、作りかけの Zip も一時ディレクトリも残さず、タグも打たない.
# 偽の wp: dist-archive --help には成功で答え、それ以外は第 2 引数のコードを実行する($2 = 展開先・$3 = Zip のパス).
expect_failure_leaves_nothing() {
	LABEL="$1"
	local wp
	wp="$(make_fake_wp "$1" "$2")"
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${wp}" -- my-plugin
	assert_rc 1
	assert_has "$3"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"
	assert_eq "" "$(git tag)" "打たれたタグ"
	assert_eq "0" "$(leftover_tmp_count)" "取り残された一時ディレクトリの数"
}

test_failures_leave_nothing_behind() {
	command -v zip >/dev/null 2>&1 || { skip "zip が無い"; return 0; }
	mk_docroot z10
	expect_failure_leaves_nothing "wp が失敗" 'echo "Error: boom" >&2; exit 1' "Error: boom"
	expect_failure_leaves_nothing "途中まで作って失敗" 'mkdir -p "$(dirname "$3")"; cd "$2" && zip -q "$3" -r . ; echo "Error: half" >&2; exit 1' "Error: half"
	expect_failure_leaves_nothing "一番上のフォルダーがスラッグでない Zip" 'mkdir -p "$(dirname "$3")"; d=$(mktemp -d); echo 1 > "$d/stray.txt"; (cd "$d" && zip -q "$3" stray.txt); echo "Success: fake"' "Zip の中に、my-plugin/ の外のファイルがあります"
}

tests_main "$@"
