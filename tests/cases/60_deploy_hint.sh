#!/usr/bin/env bash
# アップロード手順の表示のテスト(実物の `wp dist-archive` と zip・unzip が要る. 無ければ SKIP).
# dir の SSH の手順は、表示されたコマンドを疑似サーバー(別ディレクトリ・偽の HOME)で実際に実行して確かめる.
# shellcheck disable=SC2329,SC2317  # test_ で始まる関数は、tests_main が名前で呼ぶ(shellcheck には呼び出しが見えない)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

# lp(スラッグ landing)を、版 $1 に上げてコミットし、Zip を作る(タグも打たれる).
release_lp() {
	bump_lp "$1"
	run_tool landing
	assert_rc 0
}

# OUT(ツールの出力)から、「(サーバー)」から「(戻すとき)」の手前までを取り出す.
extract_server_steps() {
	printf '%s\n' "${OUT}" | awk '/^\(サーバー\)/{f=1;next} /^\(戻すとき\)/{f=0} f && NF'
}

# OUT から、「(戻すとき)」のコマンドを取り出す.
extract_rollback() {
	printf '%s\n' "${OUT}" | awk '/^\(戻すとき\)/{f=1;next} /^$/{f=0} f && NF'
}

test_plugin_and_theme_get_the_admin_upload_hint() {
	need_real_wp || return 0
	mk_docroot h1
	LABEL="plugin"; run_tool my-plugin; assert_rc 0; assert_has "プラグインの追加 > プラグインのアップロード"; assert_lacks "scp "
	LABEL="theme"; run_tool my-theme; assert_rc 0; assert_has "テーマの追加 > テーマのアップロード"
}

test_dir_hint_for_the_first_release() {
	need_real_wp || return 0
	mk_docroot h2
	run_tool landing
	assert_rc 0
	assert_has "scp ${OUTD}/landing.2.0.0.zip user@host:~/releases/"
	assert_has "mv \"\$DOCROOT/landing\" ~/releases/landing.bak"
	assert_has "メモ: 同じスラッグの前のタグが無い"
	assert_has "unzip -q landing.2.0.0.zip -d landing.2.0.0"
}

test_dir_hint_names_the_previous_version_in_version_order() {
	need_real_wp || return 0
	mk_docroot h3
	run_tool landing; assert_rc 0           # 2.0.0
	release_lp 2.1.0
	release_lp 2.9.0
	release_lp 2.10.0
	# 文字列順だと 2.10.0 は 2.1.0 の次になる. 数の並びなら 2.9.0 の次.
	assert_has "landing.bak-2.9.0"
	assert_lacks "landing.bak-2.1.0"
	assert_has "landing.failed-2.10.0"
}

test_dir_hint_commands_work_on_a_simulated_server() {
	need_real_wp || return 0
	mk_docroot h4
	run_tool landing; assert_rc 0           # 2.0.0
	release_lp 2.1.0                        # OUT は 2.1.0 の出力(前の版は 2.0.0)
	local srv="${TEST_ROOT}/server" steps rollback
	mkdir -p "${srv}/home/releases" "${srv}/docroot/landing" "${srv}/docroot/other"
	# 旧版(2.0.0): 新しい版にはないファイルを持つ.
	printf '2.0.0\n' > "${srv}/docroot/landing/VERSION"
	echo "old" > "${srv}/docroot/landing/index.html"
	echo "旧版にだけあるファイル" > "${srv}/docroot/landing/removed-later.txt"
	echo "keep" > "${srv}/docroot/other/keep.txt"
	cp "${OUTD}/landing.2.1.0.zip" "${srv}/home/releases/"   # scp の代わり
	steps="${TEST_ROOT}/server-steps.sh"
	extract_server_steps | sed "s#^DOCROOT=/path/to/public_html#DOCROOT=${srv}/docroot#" > "${steps}"
	grep -q "^DOCROOT=${srv}/docroot" "${steps}" || fail "DOCROOT の行を差し替えられません"
	# 1 行ずつ貼るのと同じく、-e なしで実行する.
	HOME="${srv}/home" "${TOOL_BASH}" "${steps}" >"${TEST_ROOT}/server-out.txt" 2>&1
	assert_eq "2.1.0" "$(cat "${srv}/docroot/landing/VERSION")" "差し替え後の版"
	assert_eq "<h1>lp 2.1.0</h1>" "$(cat "${srv}/docroot/landing/index.html")" "差し替え後の index.html"
	assert_no_file "${srv}/docroot/landing/removed-later.txt"          # 上書き展開ではないので、旧版のファイルは残らない
	assert_file "${srv}/home/releases/landing.bak-2.0.0/removed-later.txt"   # 旧版は docroot の外に退避されている
	assert_file "${srv}/docroot/other/keep.txt"
	assert_eq "landing other" "$(find "${srv}/docroot" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "docroot の中(退避した旧版が URL で見えない)"
	# 戻すとき.
	rollback="$(extract_rollback)"
	HOME="${srv}/home" DOCROOT="${srv}/docroot" "${TOOL_BASH}" -c "${rollback}" >/dev/null 2>&1
	assert_eq "2.0.0" "$(cat "${srv}/docroot/landing/VERSION")" "戻した後の版"
	assert_eq "2.1.0" "$(cat "${srv}/home/releases/landing.failed-2.1.0/VERSION")" "退避された失敗版"
}

test_dir_hint_php_fallback_line_works() {
	need_real_wp || return 0
	command -v php >/dev/null 2>&1 || { skip "php が無い"; return 0; }
	php -r 'exit(class_exists("ZipArchive") ? 0 : 1);' || { skip "php に ZipArchive が無い"; return 0; }
	mk_docroot h5
	run_tool landing; assert_rc 0
	local line work="${TEST_ROOT}/phpx"
	line="$(printf '%s\n' "${OUT}" | grep 'php -r')"
	[ -n "${line}" ] || { fail "php -r の行が表示されていません"; return 0; }
	mkdir -p "${work}" && cp "${OUTD}/landing.2.0.0.zip" "${work}/" && cd "${work}" || return 1
	"${TOOL_BASH}" -c "${line}" >/dev/null 2>&1
	assert_file "${work}/landing.2.0.0/landing/VERSION"
}

test_dir_hint_omits_the_version_check_when_version_is_not_in_the_zip() {
	need_real_wp || return 0
	mk_docroot h6
	run_tool lpx
	assert_rc 0
	assert_has "警告: Zip に lpx/VERSION が入っていないので"
	assert_lacks "cat lpx.5.0.0/lpx/VERSION"
}

# 出力先に、空白・!・%・日本語があっても、scp の行がシェルに 1 つの引数として渡ること.
# 注意: `wp dist-archive` は、出力先に ; ' " $ ( ) ` & * ? なども含むパスでは Zip を作れない(2026-10-26 に確認. 空白・!・=・,・%・日本語は通る).
#       そのため、それらの文字での確認は、Zip を安全な一時パスで作って最終のパスへ移す対応(R5)の後に test_scp_line_quotes_shell_metacharacters で足す.
test_scp_line_quotes_the_zip_path() {
	need_real_wp || return 0
	mk_docroot h9
	local weird="${TEST_ROOT}/ou t!x=y,z%日本" fakebin="${TEST_ROOT}/fakebin" line
	set_config "tag_format = {slug}/{version}
output = ${weird}
dir lp landing"
	run_tool landing
	assert_rc 0
	line="$(printf '%s\n' "${OUT}" | grep '^scp ')"
	[ -n "${line}" ] || { fail "scp の行が表示されていません"; return 0; }
	mkdir -p "${fakebin}"
	# 偽の scp: 1 つ目の引数(Zip のパス)をファイルに書く. $1 は、偽の scp の中で評価する.
	# shellcheck disable=SC2016
	printf '#!/bin/sh\nprintf "%%s" "$1" > "%s/scp-arg1"\n' "${TEST_ROOT}" > "${fakebin}/scp"
	chmod +x "${fakebin}/scp"
	# 表示された行を、そのままシェルで実行する(貼り付けと同じ).
	PATH="${fakebin}:${PATH}" "${TOOL_BASH}" -c "${line}" >/dev/null 2>&1
	assert_eq "${weird}/landing.2.0.0.zip" "$(cat "${TEST_ROOT}/scp-arg1" 2>/dev/null)" "scp に渡った Zip のパス"
}

# 出力先に ; ' " $() バッククォート & ( ) * ? があっても、表示した scp の行が 1 つの引数として渡り、コマンドが実行されないこと.
# (R5 より前は、wp dist-archive がこれらの出力先で Zip を作れず、scp の行まで届かなかった.)
test_scp_line_quotes_shell_metacharacters() {
	need_real_wp || return 0
	mk_docroot h13
	# shellcheck disable=SC2016
	local weird="${TEST_ROOT}/ou t';\$(touch ${TEST_ROOT}/pwned)\"\`x&(y)*?" fakebin="${TEST_ROOT}/fakebin2" line
	set_config "tag_format = {slug}/{version}
output = ${weird}
dir lp landing"
	run_tool landing
	assert_rc 0
	line="$(printf '%s\n' "${OUT}" | grep '^scp ')"
	[ -n "${line}" ] || { fail "scp の行が表示されていません"; return 0; }
	mkdir -p "${fakebin}"
	# shellcheck disable=SC2016
	printf '#!/bin/sh\nprintf "%%s" "$1" > "%s/scp-arg1b"\n' "${TEST_ROOT}" > "${fakebin}/scp"
	chmod +x "${fakebin}/scp"
	PATH="${fakebin}:${PATH}" "${TOOL_BASH}" -c "${line}" >/dev/null 2>&1
	assert_eq "${weird}/landing.2.0.0.zip" "$(cat "${TEST_ROOT}/scp-arg1b" 2>/dev/null)" "scp に渡った Zip のパス"
	assert_no_file "${TEST_ROOT}/pwned"
}

# 疑似サーバーを作る(旧版 2.0.0 が docroot にある). 引数 = 名前. 出力: サーバーのルート.
mk_server() {
	local srv="${TEST_ROOT}/server-$1"
	mkdir -p "${srv}/home/releases" "${srv}/docroot/landing" "${srv}/docroot/other"
	printf '2.0.0\n' > "${srv}/docroot/landing/VERSION"
	echo "old" > "${srv}/docroot/landing/index.html"
	printf '%s' "${srv}"
}

# 表示された「(サーバー)」の手順を、疑似サーバーで実行する. 引数 = サーバーのルート・Zip.
run_server_steps() {
	local srv="$1" steps="${TEST_ROOT}/steps-$$.sh"
	cp "$2" "${srv}/home/releases/"
	extract_server_steps | sed "s#^DOCROOT=/path/to/public_html#DOCROOT=${srv}/docroot#" > "${steps}"
	HOME="${srv}/home" "${TOOL_BASH}" "${steps}" >"${srv}/out.txt" 2>&1
}

# 配置先・退避先がすでにあるときは、何も壊さず、あると知らせること(入れ子にならない・展開先に混ざらない).
test_server_steps_stop_when_the_places_already_exist() {
	need_real_wp || return 0
	mk_docroot h10
	run_tool landing; assert_rc 0           # 2.0.0
	release_lp 2.1.0
	local srv
	srv="$(mk_server s1)"
	mkdir -p "${srv}/home/releases/landing.2.1.0" "${srv}/home/releases/landing.bak-2.0.0"
	echo stale > "${srv}/home/releases/landing.2.1.0/stale.txt"
	echo marker > "${srv}/home/releases/landing.bak-2.0.0/marker.txt"
	run_server_steps "${srv}" "${OUTD}/landing.2.1.0.zip"
	grep -q "すでにあります: " "${srv}/out.txt" || fail "あることを知らせていません: $(cat "${srv}/out.txt")"
	assert_eq "2.0.0" "$(cat "${srv}/docroot/landing/VERSION")" "docroot の版(差し替えない)"
	assert_no_file "${srv}/home/releases/landing.2.1.0/landing"          # 展開先に混ざらない
	assert_file "${srv}/home/releases/landing.2.1.0/stale.txt"
	assert_no_file "${srv}/home/releases/landing.bak-2.0.0/landing"      # 退避先の中に入れ子にならない
	assert_file "${srv}/home/releases/landing.bak-2.0.0/marker.txt"
}

# 退避先(.failed-<版>)がすでにあるとき、戻すコマンドは何も動かさないこと.
test_rollback_stops_when_the_failed_place_exists() {
	need_real_wp || return 0
	mk_docroot h11
	run_tool landing; assert_rc 0           # 2.0.0
	release_lp 2.1.0
	local srv rollback
	srv="$(mk_server s2)"
	run_server_steps "${srv}" "${OUTD}/landing.2.1.0.zip"
	assert_eq "2.1.0" "$(cat "${srv}/docroot/landing/VERSION")" "差し替え後の版(前提)"
	mkdir -p "${srv}/home/releases/landing.failed-2.1.0" && echo marker > "${srv}/home/releases/landing.failed-2.1.0/marker.txt"
	rollback="$(extract_rollback)"
	HOME="${srv}/home" DOCROOT="${srv}/docroot" "${TOOL_BASH}" -c "${rollback}" >"${srv}/rb.txt" 2>&1
	grep -q "すでにあります: " "${srv}/rb.txt" || fail "あることを知らせていません: $(cat "${srv}/rb.txt")"
	assert_eq "2.1.0" "$(cat "${srv}/docroot/landing/VERSION")" "戻していない(docroot はそのまま)"
	assert_no_file "${srv}/home/releases/landing.failed-2.1.0/landing"   # 入れ子にならない
}

# 表示に、配置前の確認の行(3 つの名前)があること.
test_server_steps_begin_with_an_existence_check() {
	need_real_wp || return 0
	mk_docroot h12
	run_tool landing; assert_rc 0
	release_lp 2.1.0
	# shellcheck disable=SC2088  # 表示される文字列の ~ をそのまま探す(展開しない)
	assert_has "~/releases/landing.2.1.0 ~/releases/landing.2.1.0.partial ~/releases/landing.bak-2.0.0 ~/releases/landing.failed-2.1.0"
}

# unzip が失敗した(Zip が壊れている・途中で切れた)とき、docroot の旧版を動かさないこと.
# 以前の手順は、展開に失敗しても退避の mv を実行し、docroot から旧版が消えたまま新しい版も置けない状態になりえた.
test_server_steps_do_not_touch_the_docroot_when_unzip_fails() {
	need_real_wp || return 0
	mk_docroot h14
	run_tool landing; assert_rc 0           # 2.0.0
	release_lp 2.1.0
	local srv
	srv="$(mk_server s3)"
	echo "other" > "${srv}/docroot/other/keep.txt"
	# 壊れた Zip(先頭の一部だけ)を置く.
	head -c 300 "${OUTD}/landing.2.1.0.zip" > "${TEST_ROOT}/broken.zip"
	cp "${TEST_ROOT}/broken.zip" "${TEST_ROOT}/landing.2.1.0.zip"
	run_server_steps "${srv}" "${TEST_ROOT}/landing.2.1.0.zip"
	grep -q "展開が済んでいない" "${srv}/out.txt" || fail "展開の失敗を知らせていません: $(cat "${srv}/out.txt")"
	assert_eq "2.0.0" "$(cat "${srv}/docroot/landing/VERSION")" "docroot の版(動かさない)"
	assert_eq "old" "$(cat "${srv}/docroot/landing/index.html")" "docroot の index.html"
	assert_no_file "${srv}/home/releases/landing.bak-2.0.0"            # 退避もしない
	assert_no_file "${srv}/home/releases/landing.2.1.0"                # 中途半端な展開先を、本物の名前にしない
	assert_file "${srv}/docroot/other/keep.txt"
}

test_dry_run_prints_no_hint() {
	need_real_wp || return 0
	mk_docroot h7
	run_tool landing --dry-run
	assert_rc 0
	assert_lacks "アップロードの手順"
}

test_rebuild_hint_uses_the_tag_before_the_rebuilt_one() {
	need_real_wp || return 0
	mk_docroot h8
	run_tool landing; assert_rc 0           # 2.0.0
	release_lp 2.1.0
	rm -f "${OUTD}/landing.2.1.0.zip"
	run_tool landing --rebuild 2.1.0
	assert_rc 0
	assert_has "landing.bak-2.0.0"
}

tests_main "$@"
