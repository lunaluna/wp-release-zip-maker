#!/usr/bin/env bash
# 事前の確認(--dry-run)のテスト. 組み合わせ表の「止める」の各行に当たる.
# 偽の wp(dist-archive --help にだけ答える)で動かすので、実物の wp dist-archive が無くても通る.
# shellcheck disable=SC2329,SC2317  # test_ で始まる関数は、tests_main が名前で呼ぶ(shellcheck には呼び出しが見えない)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

FAKE_WP=""

# 見本を作り、偽の wp を用意する. 引数 = 見本の名前.
pf_setup() {
	mk_docroot "$1" || return 1
	FAKE_WP="$(make_fake_wp ok 'echo "偽の wp が呼ばれた: $*" >&2; exit 1')"
}

# 偽の wp を使って、ツールを実行する.
pf() {
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${FAKE_WP}" -- "$@"
}

# --- 通る場合 ------------------------------------------------------------------------------------

test_dry_run_passes_and_creates_nothing() {
	pf_setup ok1
	pf my-plugin --dry-run
	assert_rc 0
	assert_has "[dry-run] Zip もタグも作りません"
	assert_has "版:         1.2.3"
	assert_has "タグ:       my-plugin/1.2.3 (まだありません"
	assert_has "check:      1 件とも一致"
	assert_lacks "警告"
	assert_no_file "${OUTD}"
	assert_eq "" "$(git tag)" "dry-run が打ったタグ"
}

test_dry_run_theme_and_dir() {
	pf_setup ok2
	LABEL="theme"; pf my-theme --dry-run; assert_rc 0; assert_has "版:         0.1.0"
	LABEL="dir(スラッグ landing)"; pf landing --dry-run; assert_rc 0; assert_has "版:         2.0.0"
	assert_has "check:      なし"
}

# --- 設定・対象 ----------------------------------------------------------------------------------

test_unknown_slug_stops_and_lists_known_slugs() {
	pf_setup unk
	pf nosuch --dry-run
	assert_rc 1
	assert_has "スラッグ 'nosuch' は .wp-release にありません"
	assert_has "my-plugin my-theme landing lpx nodist"
}

test_missing_distignore_stops() {
	pf_setup nodist
	pf nodist --dry-run
	assert_rc 1
	assert_has "コミット済みの .distignore がありません"
}

test_untracked_distignore_does_not_count() {
	pf_setup nodist2
	echo x > nodist/.distignore   # 作業ツリーにあるだけ(HEAD には無い)
	pf nodist --dry-run
	assert_rc 1
	assert_has "コミット済みの .distignore がありません"
}

# --- 作業ツリー ----------------------------------------------------------------------------------

test_dirty_tree_stops() {
	pf_setup dirty
	echo changed >> "${P}/my main.php"
	LABEL="変更あり"; pf my-plugin --dry-run; assert_rc 1; assert_has "未コミット・未追跡の変更があります"; assert_has "my main.php"
	git checkout -q -- .
	echo y > untracked.txt
	LABEL="未追跡あり"; pf my-plugin --dry-run; assert_rc 1; assert_has "untracked.txt"
}

test_dirty_tree_list_is_capped_at_ten() {
	pf_setup dirty2
	local i=0
	while [ "${i}" -lt 12 ]; do echo x > "untracked-${i}.txt"; i=$((i + 1)); done
	pf my-plugin --dry-run
	assert_rc 1
	assert_has "ほかに 2 件"
}

test_ignored_files_do_not_dirty_the_tree() {
	pf_setup ign
	mkdir -p "${P}/node_modules/x" && echo 1 > "${P}/node_modules/x/i.js" && echo 1 > "${P}/local.txt"   # .gitignore 済み
	pf my-plugin --dry-run
	assert_rc 0
}

# --- 版と check ----------------------------------------------------------------------------------

set_plugin_package_version() {
	printf '{\n  "version": "%s"\n}\n' "$1" > "${P}/package.json"
	gcommit "package.json $1"
}

test_check_mismatch_stops() {
	pf_setup chk
	set_plugin_package_version "1.2.2";      LABEL="1.2.2";        pf my-plugin --dry-run; assert_rc 1; assert_has "版 1.2.3 が書かれていません"; assert_has "版の表記がそろっていません"
	set_plugin_package_version "11.2.30";    LABEL="11.2.30(部分一致しない)"; pf my-plugin --dry-run; assert_rc 1; assert_has "版 1.2.3 が書かれていません"
	set_plugin_package_version "1.2.3-beta"; LABEL="1.2.3-beta(前方一致しない)"; pf my-plugin --dry-run; assert_rc 1; assert_has "版 1.2.3 が書かれていません"
	set_plugin_package_version "1.2.3";      LABEL="戻した";       pf my-plugin --dry-run; assert_rc 0
}

test_check_reports_every_problem_before_stopping() {
	pf_setup chk2
	set_config "output = ${OUTD}
plugin ${P}
check ${P}/nofile.json:version
check ${P}/package.json:[
check ${P}/package.json:nomatchhere"
	pf my-plugin --dry-run
	assert_rc 1
	assert_has "nofile.json: ファイルがありません"
	assert_has "正規表現 '[' が不正です"
	assert_has "正規表現 'nomatchhere' に一致する行がありません"
	assert_has "食い違い 3 件 / 確認 3 件"
}

test_check_applies_only_to_its_own_target() {
	pf_setup chk3
	printf '{\n  "version": "9.9.9"\n}\n' > "${TH}/package.json"
	gcommit "theme package.json is wrong"
	LABEL="プラグイン(テーマの check は関係ない)"; pf my-plugin --dry-run; assert_rc 0
	LABEL="テーマ(自分の check で止まる)"; pf my-theme --dry-run; assert_rc 1; assert_has "版 0.1.0 が書かれていません"
}

test_unreadable_version_stops() {
	pf_setup ver1
	: > lp/VERSION
	gcommit "empty VERSION"
	pf landing --dry-run
	assert_rc 1
	assert_has "lp/VERSION から版を読めません"
}

test_version_with_unusable_characters_stops() {
	pf_setup ver2
	printf 'a/b\n' > lp/VERSION
	gcommit "bad VERSION"
	pf landing --dry-run
	assert_rc 1
	assert_has "タグ名とファイル名に使えない形"
}

test_version_file_must_be_committed() {
	pf_setup ver3
	printf 'lp/VERSION\n' >> .gitignore
	git rm -q --cached lp/VERSION
	gcommit "VERSION is now ignored"
	pf landing --dry-run
	assert_rc 1
	assert_has "版を読むファイルが HEAD にありません"
}

test_version_is_read_from_the_plugin_file_with_plugin_name() {
	pf_setup ver4
	pf my-plugin --dry-run
	assert_rc 0
	assert_has "(${P}/my main.php)"
	assert_lacks "9.9.9"
}

# --- タグ・出力先の Zip ----------------------------------------------------------------------------

test_existing_tag_stops() {
	pf_setup tag1
	git tag -a my-plugin/1.2.3 -m t
	pf my-plugin --dry-run
	assert_rc 1
	assert_has "タグ my-plugin/1.2.3 はすでにあります"
	assert_has "--rebuild"
}

test_existing_tag_and_zip_stop() {
	pf_setup tag2
	git tag -a my-plugin/1.2.3 -m t
	mkdir -p "${OUTD}" && : > "${OUTD}/my-plugin.1.2.3.zip"
	pf my-plugin --dry-run
	assert_rc 1
	assert_has "タグ my-plugin/1.2.3 も Zip もすでにあります"
}

test_zip_without_tag_stops() {
	pf_setup tag3
	mkdir -p "${OUTD}" && : > "${OUTD}/my-plugin.1.2.3.zip"
	pf my-plugin --dry-run
	assert_rc 1
	assert_has "タグ my-plugin/1.2.3 は無いのに、Zip がすでにあります"
}

# --- 道具 ----------------------------------------------------------------------------------------

test_missing_wp_stops() {
	pf_setup tool1
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${TEST_ROOT}/no-such-wp" -- my-plugin --dry-run
	assert_rc 1
	assert_has "WP-CLI(${TEST_ROOT}/no-such-wp)が見つかりません"
}

test_missing_dist_archive_stops_with_install_instructions() {
	pf_setup tool2
	printf '#!/bin/sh\nexit 1\n' > "${TEST_ROOT}/wp-without-dist-archive"
	chmod +x "${TEST_ROOT}/wp-without-dist-archive"
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${TEST_ROOT}/wp-without-dist-archive" -- my-plugin --dry-run
	assert_rc 1
	assert_has "wp dist-archive が入っていません"
	assert_has "wp package install wp-cli/dist-archive-command:3.1.0"
}

# PATH から unzip だけを外したディレクトリを作り、その場所を標準出力へ出す.
# 今の PATH にあるコマンドへのリンクを、unzip 以外すべて置く(同名は PATH の先にあるものを優先).
make_path_without_unzip() {
	local d="${TEST_ROOT}/path-without-unzip" dir f
	mkdir -p "${d}"
	local IFS=:
	for dir in ${PATH}; do
		[ -d "${dir}" ] || continue
		for f in "${dir}"/*; do
			[ -x "${f}" ] && [ ! -d "${f}" ] || continue
			[ "$(basename "${f}")" = unzip ] && continue
			[ -e "${d}/$(basename "${f}")" ] || ln -s "${f}" "${d}/$(basename "${f}")"
		done
	done
	printf '%s' "${d}"
}

# unzip が無ければ、build・--rebuild・それぞれの --dry-run は止まり、何も作らない. --list は動く(Zip を扱わない).
test_missing_unzip_stops_build_and_rebuild_but_not_list() {
	pf_setup tool3
	local nounzip
	nounzip="$(make_path_without_unzip)"
	[ ! -e "${nounzip}/unzip" ] || { fail "テストの準備: PATH から unzip を外せていない"; return; }
	git tag -a my-plugin/1.2.3 -m "my-plugin 1.2.3" >/dev/null   # --rebuild のために、タグを 1 つ作っておく
	local args
	for args in "my-plugin" "my-plugin --dry-run" "my-plugin --rebuild" "my-plugin --rebuild --dry-run"; do
		LABEL="unzip なし: ${args}"
		# shellcheck disable=SC2086  # args は空白で分けて渡す
		run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${FAKE_WP}" "PATH=${nounzip}" -- ${args}
		assert_rc 1
		assert_has "unzip コマンドが見つかりません"
		assert_has "apt install unzip"
		assert_no_file "${OUTD}"
	done
	assert_eq "my-plugin/1.2.3" "$(git tag)" "unzip なしの実行が増やしたタグ"
	LABEL="unzip なし: --list"
	run_tool_env "PATH=${nounzip}" -- --list
	assert_rc 0
	assert_has "my-plugin"
	assert_lacks "unzip"
}

# --- 警告(止めない) -----------------------------------------------------------------------------

test_output_inside_the_repository_warns_unless_ignored() {
	pf_setup warn1
	set_config "output = release-out
plugin ${P}"
	LABEL="無視されていない"; pf my-plugin --dry-run; assert_rc 0; assert_has "は Git のリポジトリの中で"
	printf 'release-out/\n' >> .gitignore
	gcommit "ignore the output"
	LABEL=".gitignore 済み"; pf my-plugin --dry-run; assert_rc 0; assert_lacks "は Git のリポジトリの中で"
}

test_branch_other_than_main_warns() {
	pf_setup warn2
	git switch -q -c work
	pf my-plugin --dry-run
	assert_rc 0
	assert_has "ブランチは work です"
}

test_detached_head_warns() {
	pf_setup warn3
	git checkout -q --detach
	pf my-plugin --dry-run
	assert_rc 0
	assert_has "detached HEAD"
}

# --- コミット・コミッター --------------------------------------------------------------------------

test_repository_without_commits_stops() {
	pf_setup nocommit
	local fresh="${TEST_ROOT}/fresh"
	mkdir -p "${fresh}/p" && cd "${fresh}" && git init -q -b main || return 1
	printf '1.0.0\n' > p/VERSION
	printf 'x\n' > p/.distignore
	printf 'output = %s/o\ndir p\n' "${TEST_ROOT}" > .wp-release
	pf p --dry-run
	assert_rc 1
	assert_has "コミットがまだありません"
}

test_missing_committer_stops_before_anything_is_made() {
	pf_setup ident
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${FAKE_WP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
		GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true -- my-plugin --dry-run
	assert_rc 1
	assert_has "コミッターの名前・メールが決まっていません"
	assert_no_file "${OUTD}"
}

# --- --rebuild の事前の確認 ------------------------------------------------------------------------

test_rebuild_requires_an_existing_tag() {
	pf_setup rb1
	pf my-plugin --rebuild --dry-run
	assert_rc 1
	assert_has "タグ my-plugin/1.2.3 がありません"
	assert_has "--rebuild は、打ってあるタグから"
}

test_rebuild_dry_run_with_a_tag() {
	pf_setup rb2
	git tag -a my-plugin/1.2.3 -m t
	LABEL="--rebuild --dry-run"; pf my-plugin --rebuild --dry-run; assert_rc 0; assert_has "--rebuild(タグ my-plugin/1.2.3 から"; assert_has "あります・コミット"
	LABEL="--dry-run --rebuild(逆の順)"; pf my-plugin --dry-run --rebuild; assert_rc 0; assert_has "--rebuild(タグ my-plugin/1.2.3 から"
}

test_rebuild_ignores_a_dirty_tree_and_does_not_need_a_committer() {
	pf_setup rb3
	git tag -a my-plugin/1.2.3 -m t
	echo changed >> "${P}/my main.php"
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${FAKE_WP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
		GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true -- my-plugin --rebuild --dry-run
	assert_rc 0
}

test_rebuild_never_overwrites_a_zip() {
	pf_setup rb4
	git tag -a my-plugin/1.2.3 -m t
	mkdir -p "${OUTD}" && : > "${OUTD}/my-plugin.1.2.3.zip"
	pf my-plugin --rebuild --dry-run
	assert_rc 1
	assert_has "このツールは上書きしません"
}

test_rebuild_uses_the_head_version_unless_one_is_given() {
	pf_setup rb5
	local c1
	c1="$(git rev-parse HEAD)"
	git tag -a my-plugin/1.2.3 -m t
	bump_plugin 1.3.0
	LABEL="版を省く(HEAD は 1.3.0・タグなし)"; pf my-plugin --rebuild --dry-run; assert_rc 1; assert_has "タグ my-plugin/1.3.0 がありません"; assert_has "--rebuild <版>"
	LABEL="版を指定(1.2.3)"; pf my-plugin --rebuild 1.2.3 --dry-run; assert_rc 0; assert_has "版:         1.2.3"
	LABEL="タグのない版"; pf my-plugin --rebuild 9.9.9 --dry-run; assert_rc 1; assert_has "タグ my-plugin/9.9.9 がありません"
	LABEL="使えない形の版"; pf my-plugin --rebuild a/b --dry-run; assert_rc 1; assert_has "使えない形"
	assert_eq "${c1}" "$(git rev-parse 'my-plugin/1.2.3^{commit}')" "タグが指すコミット"
}

test_rebuild_checks_the_state_at_the_tag() {
	pf_setup rb6
	local c1
	c1="$(git rev-parse HEAD)"

	# タグの時点に .distignore が無い.
	git rm -q "${P}/.distignore" && gcommit "no distignore"
	git tag -a my-plugin/0.0.1 -m t
	git checkout -q "${c1}" -- "${P}/.distignore" && gcommit "restore distignore"
	LABEL=".distignore が無い"; pf my-plugin --rebuild 0.0.1 --dry-run; assert_rc 1; assert_has "タグ my-plugin/0.0.1 の時点でコミット済みの .distignore がありません"

	# タグ名の版と、タグの時点の版が違う(5.0.0 の名前で、版 1.2.3 のコミットを指す).
	git tag -a my-plugin/5.0.0 -m t "${c1}"
	LABEL="タグ名の版と食い違う"; pf my-plugin --rebuild 5.0.0 --dry-run; assert_rc 1; assert_has "タグ my-plugin/5.0.0 の時点の版は 1.2.3 で、タグ名の版 5.0.0 と食い違っています"

	# タグの時点で check が食い違う(版 1.4.0 だが package.json は古いまま).
	printf '<?php\n/**\n * Plugin Name: My Plugin\n * Version: 1.4.0\n */\n' > "${P}/my main.php"
	gcommit "1.4.0 without package.json"
	git tag -a my-plugin/1.4.0 -m t
	LABEL="check が食い違う"; pf my-plugin --rebuild 1.4.0 --dry-run; assert_rc 1; assert_has "タグ my-plugin/1.4.0 の"; assert_has "版の表記がそろっていません"
}

# --list(作業ツリーから読む)と --dry-run(Git の HEAD から読む)が、すべての種類で同じ版を読むこと.
# 版の読み方は 1 つの実装を、読み出し元(作業ツリー・Git の ref)の違いだけ変えて共有している. どちらかだけが変わる事故を防ぐ.
# 作業ツリーはきれいなので、2 つの読み元の内容は同じになる.
test_list_and_dry_run_read_the_same_version() {
	pf_setup same1
	local slug v_list v_dry
	for slug in my-plugin my-theme landing; do
		run_tool --list
		v_list="$(printf '%s\n' "${OUT}" | awk -v s="${slug}" '$2 == s { print $3 }')"
		pf "${slug}" --dry-run
		v_dry="$(printf '%s\n' "${OUT}" | sed -n 's/^版: *\([^ ]*\) .*$/\1/p')"
		[ -n "${v_list}" ] || fail "${slug}: --list の版を読めません"
		assert_eq "${v_list}" "${v_dry}" "${slug} の版(--list と --dry-run)"
	done
}

tests_main "$@"
