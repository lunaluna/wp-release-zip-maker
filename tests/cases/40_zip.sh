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

test_config_file_inside_the_zip_stops() {
	need_real_wp || return 0
	mk_single z8
	printf '.distignore\n' > .distignore   # .wp-release を書き忘れた状態
	gcommit "forgot .wp-release"
	run_tool solo-plugin
	assert_rc 1
	assert_has "solo-plugin/.wp-release"
	assert_has ".distignore に書いて"
	assert_no_file "${OUTD}/solo-plugin.0.5.0.zip"
	assert_eq "0" "$(git tag | wc -l | tr -d ' ')" "タグの数(何も作らない)"
}

# --- 配布してはいけないファイル -----------------------------------------------------------------

# 配布禁止の名前(止める). 例外はなく、外すには .distignore に書く. 形: プラグインの下のパス(1 行に 1 つ).
FORBIDDEN_FILES='.env
.env.local
.env.example
config/wp-config.php
id_rsa
id_ed25519
keys/server.pem
keys/a.key
keys/a.p12
keys/a.pfx
.htpasswd
.npmrc
.netrc
.git-credentials
dump.sql
dump.sql.gz
db/x.dump
a.bak
a.orig
a~
a.swp
.DS_Store
.svn/entries'

# プラグインの下に、配布禁止のファイルを作ってコミットする. 引数 = ファイルの一覧(1 行に 1 つ).
commit_forbidden_files() {
	local f
	while IFS= read -r f; do
		mkdir -p "${P}/$(dirname "${f}")" && echo secret > "${P}/${f}"
	done <<LIST
$1
LIST
	gcommit "forbidden files"
}

test_forbidden_files_stop_the_build() {
	need_real_wp || return 0
	mk_docroot z11
	commit_forbidden_files "${FORBIDDEN_FILES}"
	run_tool my-plugin
	assert_rc 1
	local f
	# 止めるときは、見つけたものをすべて表示する(先頭の数行だけを見る show_out ではなく、OUT 全体を調べる).
	while IFS= read -r f; do
		assert_has "my-plugin/${f}"
	done <<LIST
${FORBIDDEN_FILES}
LIST
	assert_has "配布してはいけないファイル"
	assert_has ".distignore に書いて"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"
	assert_eq "0" "$(git tag | wc -l | tr -d ' ')" "タグの数(何も作らない)"
}

test_forbidden_names_are_matched_case_insensitively() {
	need_real_wp || return 0
	mk_docroot z12
	commit_forbidden_files 'WP-CONFIG.PHP
Dump.SQL
.ENV'
	run_tool my-plugin
	assert_rc 1
	assert_has "my-plugin/WP-CONFIG.PHP"
	assert_has "my-plugin/Dump.SQL"
	assert_has "my-plugin/.ENV"
}

test_forbidden_files_pass_when_listed_in_distignore() {
	need_real_wp || return 0
	mk_docroot z13
	commit_forbidden_files "${FORBIDDEN_FILES}"
	# 禁止の名前を、すべて .distignore で外す(設定に許可リストは無い. 外す方法はこれだけ).
	printf '/src\npackage.json\n.distignore\nnode_modules\n.env*\nwp-config.php\nid_rsa\nid_ed25519\n*.pem\n*.key\n*.p12\n*.pfx\n.htpasswd\n.npmrc\n.netrc\n.git-credentials\n*.sql\n*.sql.gz\n*.dump\n*.bak\n*.orig\n*~\n*.swp\n.DS_Store\n.svn\n' > "${P}/.distignore"
	gcommit "distignore"
	run_tool my-plugin
	assert_rc 0
	assert_lacks "配布してはいけないファイル"
	local f z="${OUTD}/my-plugin.1.2.3.zip"
	while IFS= read -r f; do
		if zip_has "${z}" "my-plugin/${f}"; then fail "除いたはずのファイルが入っています: ${f}"; fi
	done <<LIST
${FORBIDDEN_FILES}
LIST
}

test_rebuild_checks_forbidden_files_in_the_tag() {
	need_real_wp || return 0
	mk_docroot z14
	commit_forbidden_files '.env'
	git tag my-plugin/1.2.3   # 禁止ファイルを含むコミットに、軽量タグを付ける
	run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "my-plugin/.env"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"
}

# 禁止ではない、ドットで始まるファイルとディレクトリは、警告だけで止めない(.htaccess と .well-known は dir のときだけ警告も出さない).
test_other_dotfiles_only_warn() {
	need_real_wp || return 0
	mk_docroot z15
	echo 1 > "${P}/.gitkeep"
	echo 1 > "${P}/.htaccess"
	mkdir -p "${P}/.hidden" "${P}/assets/.cache"
	echo 1 > "${P}/.hidden/x.txt"
	echo 1 > "${P}/assets/.cache/y.txt"
	gcommit "dotfiles"
	run_tool my-plugin
	assert_rc 0
	assert_has "警告: ドットで始まるファイル・ディレクトリが入っています"
	assert_has "my-plugin/.gitkeep"
	assert_has "my-plugin/.htaccess"
	assert_has "my-plugin/.hidden"
	assert_has "my-plugin/assets/.cache"
	assert_file "${OUTD}/my-plugin.1.2.3.zip"
}

test_htaccess_and_well_known_are_fine_in_a_dir() {
	need_real_wp || return 0
	mk_docroot z16
	echo 'Options -Indexes' > lp/.htaccess
	mkdir -p lp/.well-known && echo 'Contact: x' > lp/.well-known/security.txt
	gcommit "htaccess"
	run_tool landing
	assert_rc 0
	assert_lacks "警告:"   # 直下の内訳には .htaccess が出るので、警告の有無だけを見る
	local z="${OUTD}/landing.2.0.0.zip"
	zip_has "${z}" "landing/.htaccess" || fail ".htaccess が入っていません"
	zip_has "${z}" "landing/.well-known/security.txt" || fail ".well-known/security.txt が入っていません"
	# dir でも、ほかのドットのファイルは警告する.
	echo 1 > lp/.gitkeep; gcommit "gitkeep"; bump_lp 2.0.1
	run_tool landing
	assert_rc 0
	assert_has "landing/.gitkeep"
}

# --- 出力 Zip の排他(上書きしない) --------------------------------------------------------------

# 出力先に、壊れたシンボリックリンク(行き先が無い)が同名であれば、その先へ書かず、すでにあるものとして止めること.
test_dangling_symlink_at_the_output_path_is_not_followed() {
	need_real_wp || return 0
	mk_docroot e1
	mkdir -p "${OUTD}" && ln -s "${TEST_ROOT}/victim.zip" "${OUTD}/my-plugin.1.2.3.zip"
	run_tool my-plugin
	assert_rc 1
	assert_has "Zip がすでにあります"
	assert_no_file "${TEST_ROOT}/victim.zip"                         # リンクの先に書いていない
	[ -L "${OUTD}/my-plugin.1.2.3.zip" ] || fail "シンボリックリンクが消えました"
	assert_eq "0" "$(git tag | wc -l | tr -d ' ')" "タグの数(何も作らない)"
	# --rebuild も同じ.
	git tag my-plugin/1.2.3
	LABEL="--rebuild"; run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "Zip がすでにあります"
	assert_no_file "${TEST_ROOT}/victim.zip"
}

# 確認のあと、作っている間に別のプロセスが同じ名前のファイルを作っても、それを上書きしないこと(確認と作成が別の操作になる隙間).
# 偽の wp が、本物の wp dist-archive を呼んだあとで、最終の Zip のパスに別のファイルを置く.
test_a_file_created_during_the_build_is_not_overwritten() {
	need_real_wp || return 0
	mk_docroot e2
	local final="${OUTD}/my-plugin.1.2.3.zip" real fake
	real="$(command -v wp)"
	fake="$(make_fake_wp race "'${real}' \"\$@\"; rc=\$?; mkdir -p '${OUTD}'; echo competitor > '${final}'; exit \$rc")"
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${fake}" -- my-plugin
	assert_rc 1
	assert_has "すでにあります"
	assert_eq "competitor" "$(cat "${final}")" "別のプロセスが作ったファイル(上書きしない)"
	assert_eq "0" "$(git tag | wc -l | tr -d ' ')" "タグの数(何も作らない)"
	assert_eq "1" "$(find "${OUTD}" -mindepth 1 | wc -l | tr -d ' ')" "出力先の中のファイル(一時ファイルを残さない)"
	assert_eq "0" "$(leftover_tmp_count)" "取り残した一時ディレクトリ"
}

# 同じものを同時に 2 つ実行しても、Zip とタグが 1 つずつできて、片方は止まること.
test_parallel_runs_make_exactly_one_zip_and_tag() {
	need_real_wp || return 0
	mk_docroot e3
	("${TOOL_BASH}" "${TOOL}" my-plugin >"${TEST_ROOT}/par1.txt" 2>&1; echo $? > "${TEST_ROOT}/par1.rc") &
	("${TOOL_BASH}" "${TOOL}" my-plugin >"${TEST_ROOT}/par2.txt" 2>&1; echo $? > "${TEST_ROOT}/par2.rc") &
	wait
	assert_eq "0 1" "$(cat "${TEST_ROOT}/par1.rc" "${TEST_ROOT}/par2.rc" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "終了コード(1 つが成功・1 つが停止)"
	assert_eq "1" "$(find "${OUTD}" -mindepth 1 | wc -l | tr -d ' ')" "出力先の中のファイル"
	assert_eq "my-plugin/1.2.3" "$(git tag)" "タグ"
	unzip -tq "${OUTD}/my-plugin.1.2.3.zip" >/dev/null 2>&1 || fail "Zip が壊れています"
}

# 作った Zip の権限は、umask どおりになる(一時ファイルの 0600 のままにならない).
test_the_zip_gets_the_umask_permissions() {
	need_real_wp || return 0
	mk_docroot e4
	umask 022
	run_tool my-plugin
	assert_rc 0
	# shellcheck disable=SC2012  # ファイル名は固定の ASCII. 権限の文字列(先頭の 10 文字)を読むのに ls -l が手軽
	assert_eq "-rw-r--r--" "$(ls -l "${OUTD}/my-plugin.1.2.3.zip" | cut -c1-10)" "Zip の権限"
}

# 出力先に、シェルの特殊文字(; ' " $() バッククォート & ( ) * ? など)があっても、Zip を作れること.
# 以前は wp dist-archive が、これらを含む出力先を扱えず失敗した(Zip を安全な一時パスで作って、最終のパスへ移すようにして解消).
test_output_path_with_shell_metacharacters() {
	need_real_wp || return 0
	mk_docroot e5
	local weird="${TEST_ROOT}/ou t';\$(touch ${TEST_ROOT}/pwned)\"\`x&(y)*?"
	set_config "tag_format = {slug}/{version}
output = ${weird}
plugin ${P}"
	run_tool my-plugin
	assert_rc 0
	assert_file "${weird}/my-plugin.1.2.3.zip"
	assert_no_file "${TEST_ROOT}/pwned"
	assert_eq "1" "$(find "${weird}" -mindepth 1 | wc -l | tr -d ' ')" "出力先の中のファイル(一時ファイルを残さない)"
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
