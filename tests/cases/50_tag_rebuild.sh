#!/usr/bin/env bash
# 注釈付きタグと --rebuild のテスト(実物の `wp dist-archive` と zip・unzip が要る. 無ければ SKIP).
# shellcheck disable=SC2329,SC2317  # test_ で始まる関数は、tests_main が名前で呼ぶ(shellcheck には呼び出しが見えない)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

# タグのメッセージの中の、見出し($2)の値を出す(例: SHA-256). $1 = タグ名.
# ツールの tag_recorded_field と似た処理だが、意図して実装に頼らず、テスト側で独立に読む(同じ誤りを、実装とテストが同時に持たないため).
tag_field() {
	git tag -l --format='%(contents)' "$1" | sed -n "s/^$2: *//p" | head -n 1
}

# --- 通常実行のタグ --------------------------------------------------------------------------------

test_build_creates_an_annotated_tag_with_the_record() {
	need_real_wp || return 0
	mk_docroot t1
	run_tool my-plugin
	assert_rc 0
	local tag="my-plugin/1.2.3" z="${OUTD}/my-plugin.1.2.3.zip"
	assert_eq "tag" "$(git cat-file -t "${tag}")" "タグの種類(tag = 注釈付き)"
	assert_eq "$(git rev-parse HEAD)" "$(git rev-parse "${tag}^{commit}")" "タグが指すコミット"
	assert_eq "my-plugin 1.2.3" "$(git tag -l --format='%(contents:subject)' "${tag}")" "タグのメッセージの 1 行目"
	assert_eq "my-plugin.1.2.3.zip" "$(tag_field "${tag}" "Zip")" "記録された Zip の名前"
	assert_eq "$(sha256_file "${z}")" "$(tag_field "${tag}" "SHA-256")" "記録された Zip の SHA-256"
	printf '%s' "$(tag_field "${tag}" "Content-SHA-256")" | grep -qE '^[0-9a-f]{64}$' || fail "Content-SHA-256 が 64 桁の 16 進数ではありません"
	printf '%s' "$(tag_field "${tag}" "Built-with")" | grep -q '^wp-release-zip-maker ' || fail "Built-with がありません"
	assert_has "を打ちました(注釈付き"
	assert_has "push はしていません"
}

test_each_target_gets_its_own_tag() {
	need_real_wp || return 0
	mk_docroot t2
	run_tool my-plugin; assert_rc 0
	run_tool my-theme; assert_rc 0
	assert_eq "my-plugin/1.2.3 my-theme/0.1.0" "$(git tag | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "打たれたタグ"
}

test_tag_format_is_applied() {
	need_real_wp || return 0
	mk_docroot t3
	set_config "tag_format = {slug}@{version}
output = ${OUTD}
plugin ${P}"
	run_tool my-plugin
	assert_rc 0
	assert_eq "my-plugin@1.2.3" "$(git tag)" "打たれたタグ"
}

test_single_target_tag_is_a_bare_version() {
	need_real_wp || return 0
	mk_single t4
	run_tool solo-plugin
	assert_rc 0
	assert_eq "0.5.0" "$(git tag)" "打たれたタグ(v を付けない素の版番号)"
}

test_missing_committer_stops_before_the_zip() {
	need_real_wp || return 0
	mk_docroot t5
	run_tool_env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true -- my-plugin
	assert_rc 1
	assert_has "コミッターの名前・メールが決まっていません"
	assert_no_file "${OUTD}"
	assert_eq "" "$(git tag)" "打たれたタグ"
}

test_tag_failure_removes_the_zip() {
	need_real_wp || return 0
	mk_docroot t6
	# タグの署名を求め、壊れた gpg を指して、タグの作成だけを失敗させる.
	run_tool_env GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=tag.gpgSign GIT_CONFIG_VALUE_0=true GIT_CONFIG_KEY_1=gpg.program "GIT_CONFIG_VALUE_1=$(command -v false)" -- my-plugin
	assert_rc 1
	assert_has "を打てませんでした(Zip は消しました)"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"
	assert_eq "" "$(git tag)" "打たれたタグ"
	assert_eq "0" "$(leftover_tmp_count)" "取り残された一時ディレクトリの数"
}

# --- 署名付きタグ(--sign) -----------------------------------------------------------------------
# この環境には gpg が無く、実際の署名はテストできない. 代わりに、Git が期待する形(署名を標準出力・状態を標準エラーの [GNUPG:] SIG_CREATED)を返す偽の gpg を使い、
# ツールが「git tag -s で打つ」ことと、失敗したときの後始末を確かめる(署名そのものの正しさは Git と gpg の責任).

# 偽の gpg を作る. 出力: そのパス.
make_fake_gpg() {
	local path="${TEST_ROOT}/fake-gpg"
	printf '#!/bin/sh\ncat > /dev/null\necho "-----BEGIN PGP SIGNATURE-----"\necho "ZmFrZQ=="\necho "-----END PGP SIGNATURE-----"\necho "[GNUPG:] SIG_CREATED D 1 8 00 0 FAKE" >&2\n' > "${path}"
	chmod +x "${path}"
	printf '%s' "${path}"
}

# --sign で、署名付きのタグが打たれること. 付けなければ、署名されないこと(gpg.program を指していても).
test_sign_makes_a_signed_tag() {
	need_real_wp || return 0
	mk_docroot g1
	local gpg
	gpg="$(make_fake_gpg)"
	run_tool_env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gpg.program "GIT_CONFIG_VALUE_0=${gpg}" -- my-plugin --sign
	assert_rc 0
	git cat-file -p my-plugin/1.2.3 | grep -q 'BEGIN PGP SIGNATURE' || fail "タグに署名がありません"
	assert_eq "my-plugin 1.2.3" "$(git tag -l --format='%(contents:subject)' my-plugin/1.2.3)" "タグの 1 行目(署名があっても同じ)"
	assert_has "署名付き"
	mk_docroot g2
	LABEL="付けない"; run_tool_env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gpg.program "GIT_CONFIG_VALUE_0=${gpg}" -- my-plugin
	assert_rc 0
	git cat-file -p my-plugin/1.2.3 | grep -q 'BEGIN PGP SIGNATURE' && fail "--sign なしなのに、署名されています"
	assert_lacks "署名付き"
}

# 署名に失敗したら(gpg が無い・鍵が無い・パスフレーズの入力に失敗など)、タグも Zip も作らないこと.
test_sign_failure_removes_everything() {
	need_real_wp || return 0
	mk_docroot g3
	run_tool_env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gpg.program "GIT_CONFIG_VALUE_0=$(command -v false)" -- my-plugin --sign --manifest
	assert_rc 1
	assert_has "を打てませんでした(Zip は消しました)"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"
	assert_no_file "${OUTD}/my-plugin.1.2.3.manifest.txt"
	assert_eq "" "$(git tag)" "打たれたタグ"
	assert_eq "0" "$(leftover_tmp_count)" "取り残された一時ディレクトリの数"
}

# --sign は、タグを打つときだけ指定できる(--rebuild・--list では誤り). --dry-run では、署名する予定だと表示する.
test_sign_option_usage() {
	need_real_wp || return 0
	mk_docroot g4
	LABEL="--rebuild"; run_tool my-plugin --rebuild --sign; assert_rc 2; assert_has "--sign は"
	LABEL="--list"; run_tool --list --sign; assert_rc 2; assert_has "--list には"
	LABEL="--dry-run"; run_tool my-plugin --sign --dry-run; assert_rc 0; assert_has "署名:"
	assert_no_file "${OUTD}"
}

# --- --rebuild -----------------------------------------------------------------------------------

test_rebuild_reproduces_the_content_without_a_new_tag() {
	need_real_wp || return 0
	mk_docroot r1
	run_tool my-plugin; assert_rc 0
	local before_tag names_before
	before_tag="$(git rev-parse my-plugin/1.2.3)"
	names_before="$(zip_names "${OUTD}/my-plugin.1.2.3.zip" | LC_ALL=C sort)"
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	run_tool my-plugin --rebuild
	assert_rc 0
	assert_has "内容の指紋が、タグの記録と一致しました"
	assert_eq "${names_before}" "$(zip_names "${OUTD}/my-plugin.1.2.3.zip" | LC_ALL=C sort)" "作り直した Zip のファイル一覧"
	assert_eq "${before_tag}" "$(git rev-parse my-plugin/1.2.3)" "タグ(変わらない)"
	assert_eq "1" "$(git tag | wc -l | tr -d ' ')" "タグの数"
}

test_rebuild_never_overwrites_an_existing_zip() {
	need_real_wp || return 0
	mk_docroot r2
	run_tool my-plugin; assert_rc 0
	run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "このツールは上書きしません"
}

test_rebuild_builds_from_the_tag_not_the_worktree() {
	need_real_wp || return 0
	mk_docroot r3
	run_tool my-plugin; assert_rc 0
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	echo "changed" >> "${P}/my main.php"   # 作業ツリーが汚れている(コミットしていない)
	echo "ignored" > "${P}/local.txt"
	run_tool my-plugin --rebuild
	assert_rc 0
	zip_cat "${OUTD}/my-plugin.1.2.3.zip" "my-plugin/my main.php" | grep -q changed && fail "作業ツリーの未コミットの変更が Zip に入っています"
	if zip_has "${OUTD}/my-plugin.1.2.3.zip" "my-plugin/local.txt"; then fail "無視されたファイルが Zip に入っています"; fi
}

test_rebuild_an_older_version_after_the_version_moved_on() {
	need_real_wp || return 0
	mk_docroot r4
	run_tool my-plugin; assert_rc 0
	bump_plugin 1.3.0
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	LABEL="版を省く(HEAD は 1.3.0 でタグなし)"; run_tool my-plugin --rebuild; assert_rc 1; assert_has "タグ my-plugin/1.3.0 がありません"
	LABEL="--rebuild 1.2.3"; run_tool my-plugin --rebuild 1.2.3; assert_rc 0
	zip_cat "${OUTD}/my-plugin.1.2.3.zip" "my-plugin/my main.php" | grep -q "Version: 1.2.3" || fail "作り直した Zip が 1.2.3 の内容ではありません"
	assert_has "内容の指紋が、タグの記録と一致しました"
}

# 内容の指紋だけが違うタグに付け替える(Zip は消す). 引数 = 付け替える指紋の値(64 桁).
retag_with_fingerprint() {
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	printf 'my-plugin 1.2.3\n\nZip: my-plugin.1.2.3.zip\nSHA-256: %064d\nContent-SHA-256: %s\nBuilt-with: x\n' 0 "$1" |
		git tag -f -a -F - my-plugin/1.2.3 HEAD >/dev/null
}

test_rebuild_stops_on_a_fingerprint_mismatch() {
	need_real_wp || return 0
	mk_docroot r5
	run_tool my-plugin; assert_rc 0
	retag_with_fingerprint "$(printf '%064d' 1)"
	run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "内容の指紋が、タグの記録と違います"
	assert_has "$(printf '%064d' 1)"
	assert_has "--allow-content-change"
	assert_lacks "アップロードの手順"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"   # 違う内容の Zip を、配布できる名前で残さない
}

test_rebuild_allows_a_fingerprint_mismatch_when_told_to() {
	need_real_wp || return 0
	mk_docroot r5b
	run_tool my-plugin; assert_rc 0
	retag_with_fingerprint "$(printf '%064d' 1)"
	run_tool my-plugin --rebuild --allow-content-change
	assert_rc 0
	assert_has "内容の指紋が、タグの記録と違います"
	assert_has "--allow-content-change が指定されているので続行します"
	assert_file "${OUTD}/my-plugin.1.2.3.zip"
}

test_allow_content_change_needs_rebuild() {
	need_real_wp || return 0
	mk_docroot r5c
	run_tool my-plugin --allow-content-change
	assert_rc 2
	assert_has "--allow-content-change は --rebuild のときだけ"
	assert_eq "0" "$(git tag | wc -l | tr -d ' ')" "タグの数(何も作らない)"
}

# CRC-32 が同じ別の内容でも、指紋が変わること(CRC-32 は、同じ値になる別の内容を意図的に作れるため).
# "plumless" と "buckeroo" は、どちらも CRC-32 = 4ddb0c25.
test_fingerprint_tells_apart_files_with_the_same_crc32() {
	need_real_wp || return 0
	mk_docroot f1
	printf 'plumless' > "${P}/payload.txt"; gcommit "payload a"
	run_tool my-plugin; assert_rc 0
	local fp_a crc_a
	fp_a="$(tag_field my-plugin/1.2.3 Content-SHA-256)"
	crc_a="$(unzip -v "${OUTD}/my-plugin.1.2.3.zip" | awk '/payload.txt$/ {print $7}')"
	mk_docroot f2
	printf 'buckeroo' > "${P}/payload.txt"; gcommit "payload b"
	run_tool my-plugin; assert_rc 0
	local fp_b crc_b
	fp_b="$(tag_field my-plugin/1.2.3 Content-SHA-256)"
	crc_b="$(unzip -v "${OUTD}/my-plugin.1.2.3.zip" | awk '/payload.txt$/ {print $7}')"
	assert_eq "4ddb0c25" "${crc_a}" "a の CRC-32(テストの前提)"
	assert_eq "${crc_a}" "${crc_b}" "b の CRC-32(テストの前提: a と同じ)"
	[ "${fp_a}" != "${fp_b}" ] || fail "CRC-32 が同じ別の内容で、指紋が同じになりました(${fp_a})"
}

# ファイルの内容・名前・実行権限のどれが違っても、指紋が変わること.
test_fingerprint_changes_with_content_name_and_mode() {
	need_real_wp || return 0
	local base v
	mk_docroot f3
	run_tool my-plugin; assert_rc 0
	base="$(tag_field my-plugin/1.2.3 Content-SHA-256)"
	mk_docroot f4; echo 2 > "${P}/assets/app.js"; gcommit "content"
	run_tool my-plugin; assert_rc 0
	v="$(tag_field my-plugin/1.2.3 Content-SHA-256)"
	[ "${base}" != "${v}" ] || fail "ファイルの内容が違うのに、指紋が同じです"
	mk_docroot f5; git mv "${P}/assets/app.js" "${P}/assets/app2.js"; gcommit "name"
	run_tool my-plugin; assert_rc 0
	v="$(tag_field my-plugin/1.2.3 Content-SHA-256)"
	[ "${base}" != "${v}" ] || fail "ファイル名が違うのに、指紋が同じです"
	mk_docroot f6; chmod +x "${P}/assets/app.js"; gcommit "mode"
	run_tool my-plugin; assert_rc 0
	v="$(tag_field my-plugin/1.2.3 Content-SHA-256)"
	[ "${base}" != "${v}" ] || fail "実行権限が違うのに、指紋が同じです"
}

# 作り直すときの wp dist-archive(や zip)が、元と違う内容を作ったとき(版違いで、入るファイルが変わる場合を想定)、止めること.
# 偽の wp が、本物の wp dist-archive の出力に、元には無かったファイルを足す.
test_rebuild_stops_when_the_builder_produces_different_content() {
	need_real_wp || return 0
	mk_docroot r9
	run_tool my-plugin; assert_rc 0
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	local real fake
	real="$(command -v wp)"
	# mktemp は使わない(出力先の Zip と同じディレクトリの下に、作業用のディレクトリを作る).
	fake="$(make_fake_wp differ "[ \"\$1\" = dist-archive ] || exec '${real}' \"\$@\"; '${real}' \"\$@\" || exit \$?; d=\"\$(dirname \"\$3\")/work\$\$\" && mkdir -p \"\$d/my-plugin\" && echo extra > \"\$d/my-plugin/extra.txt\" && (cd \"\$d\" && zip -q \"\$3\" my-plugin/extra.txt); rm -rf \"\$d\"")"
	LABEL="止める"; run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${fake}" -- my-plugin --rebuild
	assert_rc 1
	assert_has "内容の指紋が、タグの記録と違います"
	assert_has "--allow-content-change"
	assert_no_file "${OUTD}/my-plugin.1.2.3.zip"
	LABEL="許可する"; run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${fake}" -- my-plugin --rebuild --allow-content-change
	assert_rc 0
	zip_has "${OUTD}/my-plugin.1.2.3.zip" "my-plugin/extra.txt" || fail "足したファイルが入っていません(テストの前提)"
}

# 今のタグのメッセージの、内容の指紋($1)だけを差し替えたタグに付け替える(道具の版の欄はそのまま). Zip は消す.
retag_with_digest() {
	local msg
	msg="$(git tag -l --format='%(contents)' my-plugin/1.2.3 | sed "s/^Content-SHA-256: .*/Content-SHA-256: $1/")"
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	printf '%s\n' "${msg}" | git tag -f -a -F - my-plugin/1.2.3 HEAD >/dev/null
}

# タグに、Zip を作ったときの WP-CLI・dist-archive・zip の版が記録されること(作り直しで内容が違ったときの手がかり).
test_tag_records_the_tool_versions() {
	need_real_wp || return 0
	mk_docroot b1
	run_tool my-plugin; assert_rc 0
	local tag="my-plugin/1.2.3" wp_v zip_v
	wp_v="$(wp --version 2>/dev/null | grep -v -i deprecated | sed -n 's/^WP-CLI *//p' | head -n 1)"
	zip_v="$(zip -v 2>&1 | sed -n 's/^This is Zip \([^ ]*\).*$/\1/p' | head -n 1)"
	[ -n "${wp_v}" ] && [ -n "${zip_v}" ] || { fail "テストの前提: wp・zip の版を読めません"; return 0; }
	assert_eq "${wp_v}" "$(tag_field "${tag}" "WP-CLI")" "記録された WP-CLI の版"
	assert_eq "${zip_v}" "$(tag_field "${tag}" "zip")" "記録された zip の版"
	printf '%s' "$(tag_field "${tag}" "dist-archive")" | grep -qE '^[0-9]+\.[0-9]+' || fail "dist-archive の版が記録されていません: $(tag_field "${tag}" "dist-archive")"
	# ツールは installed.json から読む(速い). 以前の読み方(wp package list)と同じ値になること.
	local list_v
	list_v="$(wp package list --fields=name,version --format=csv 2>/dev/null | sed -n 's#^wp-cli/dist-archive-command,v\{0,1\}##p' | head -n 1)"
	[ -z "${list_v}" ] || assert_eq "${list_v}" "$(tag_field "${tag}" "dist-archive")" "wp package list と同じ dist-archive の版"
}

# dist-archive の版の読み方(組み合わせ表の各行). installed.json から読めればそれを、読めなければ wp package list の値を記録する.
# 偽の wp: dist-archive と --version は本物に渡し、package path は場面ごとの動き、package list は 'v1.1.1' を返す.
test_dist_archive_version_sources() {
	need_real_wp || return 0
	local real case_name pkgdir path_code expect fake n=0
	real="$(command -v wp)"
	for case_name in composer2 composer1 no_entry no_json path_fails no_version_in_entry; do
		n=$((n + 1))
		pkgdir="${TEST_ROOT}/pkgdir-${case_name}"
		mkdir -p "${pkgdir}/vendor/composer"
		path_code="echo '${pkgdir}/'"
		expect="1.1.1"
		case "${case_name}" in
			composer2)
				# Composer 2 の形({"packages": [...]}). 先頭の v は取る.
				printf '{\n    "packages": [\n        {\n            "name": "other/pkg",\n            "version": "5.5.5"\n        },\n        {\n            "name": "wp-cli/dist-archive-command",\n            "version": "v9.8.7",\n            "version_normalized": "9.8.7.0"\n        }\n    ]\n}\n' >"${pkgdir}/vendor/composer/installed.json"
				expect="9.8.7"
				;;
			composer1)
				# Composer 1 の形(配列). 版に v が無い場合.
				printf '[\n    {\n        "name": "wp-cli/dist-archive-command",\n        "version": "9.8.6"\n    }\n]\n' >"${pkgdir}/vendor/composer/installed.json"
				expect="9.8.6"
				;;
			no_entry)
				printf '{\n    "packages": [\n        {\n            "name": "other/pkg",\n            "version": "5.5.5"\n        }\n    ]\n}\n' >"${pkgdir}/vendor/composer/installed.json"
				;;
			no_json) ;;
			path_fails) path_code="exit 1" ;;
			no_version_in_entry)
				# dist-archive の中に version が無い. 次のパッケージの版(5.5.5)を拾わないこと.
				printf '{\n    "packages": [\n        {\n            "name": "wp-cli/dist-archive-command"\n        },\n        {\n            "name": "other/pkg",\n            "version": "5.5.5"\n        }\n    ]\n}\n' >"${pkgdir}/vendor/composer/installed.json"
				;;
		esac
		fake="$(make_fake_wp "dav-${case_name}" "case \"\$1\" in dist-archive | --version) exec '${real}' \"\$@\" ;; esac
if [ \"\$1\" = package ] && [ \"\$2\" = path ]; then ${path_code}; exit 0; fi
if [ \"\$1\" = package ] && [ \"\$2\" = list ]; then printf 'name,version\nwp-cli/dist-archive-command,v1.1.1\n'; exit 0; fi
exit 1")"
		mk_docroot "dav${n}"
		LABEL="${case_name}"
		run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${fake}" -- my-plugin
		assert_rc 0
		assert_eq "${expect}" "$(tag_field my-plugin/1.2.3 "dist-archive")" "記録された dist-archive の版"
	done
}

# 版を調べられないときは、unknown と記録して、Zip の作成は続ける(版の記録のために止めない).
test_tag_records_unknown_when_a_version_cannot_be_read() {
	need_real_wp || return 0
	mk_docroot b2
	local real fake
	real="$(command -v wp)"
	# dist-archive の呼び出しだけ本物に渡し、--version・package list は失敗させる.
	fake="$(make_fake_wp noversion "[ \"\$1\" = dist-archive ] && exec '${real}' \"\$@\"; exit 1")"
	run_tool_env "WP_RELEASE_ZIP_MAKER_WP=${fake}" -- my-plugin
	assert_rc 0
	assert_eq "unknown" "$(tag_field my-plugin/1.2.3 "WP-CLI")" "WP-CLI の版"
	assert_eq "unknown" "$(tag_field my-plugin/1.2.3 "dist-archive")" "dist-archive の版"
}

# 内容が違って止めるとき、道具の版を「タグの記録 → 今回」で並べ、違うものに印を付けること.
test_rebuild_mismatch_compares_the_tool_versions() {
	need_real_wp || return 0
	mk_docroot b3
	run_tool my-plugin; assert_rc 0
	# 記録の WP-CLI と dist-archive の版を、今と違う値にして、指紋も違う値にする.
	local msg
	msg="$(git tag -l --format='%(contents)' my-plugin/1.2.3 | sed -e "s/^Content-SHA-256: .*/Content-SHA-256: $(printf '%064d' 1)/" -e 's/^WP-CLI: .*/WP-CLI: 1.0.0/' -e 's/^dist-archive: .*/dist-archive: 0.0.1/')"
	rm -f "${OUTD}/my-plugin.1.2.3.zip"
	printf '%s\n' "${msg}" | git tag -f -a -F - my-plugin/1.2.3 HEAD >/dev/null
	run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "使った道具の版(タグの記録 → 今回)"
	printf '%s\n' "${OUT}" | grep -aE 'WP-CLI: +1\.0\.0 →' | grep -aq '違います' || fail "WP-CLI の違いに印が付いていません"
	printf '%s\n' "${OUT}" | grep -aE 'dist-archive: +0\.0\.1 →' | grep -aq '違います' || fail "dist-archive の違いに印が付いていません"
	printf '%s\n' "${OUT}" | grep -aE '^ +zip: ' | grep -aq '違います' && fail "同じ zip の版に、違うという印が付いています"
}

# 道具の版がすべて同じなのに内容が違うときは、そう伝える(原因は版以外にある).
test_rebuild_mismatch_says_when_the_tool_versions_are_the_same() {
	need_real_wp || return 0
	mk_docroot b4
	run_tool my-plugin; assert_rc 0
	retag_with_digest "$(printf '%064d' 1)"
	run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "道具の版はすべて同じです"
	assert_lacks "違います)"
}

# 旧タグ(道具の版の記録がない)では、記録なしと表示する.
test_rebuild_mismatch_with_no_recorded_tool_versions() {
	need_real_wp || return 0
	mk_docroot b5
	run_tool my-plugin; assert_rc 0
	retag_with_fingerprint "$(printf '%064d' 1)"   # 道具の版の欄が無いタグ
	run_tool my-plugin --rebuild
	assert_rc 1
	assert_has "(記録なし)"
}

test_rebuild_without_a_recorded_fingerprint() {
	need_real_wp || return 0
	mk_docroot r6
	git tag my-plugin/1.2.3   # 軽量タグ(このツールで打ったものではない)
	run_tool my-plugin --rebuild
	assert_rc 0
	assert_has "内容の指紋(Content-SHA-256)の記録がありません"
}

test_rebuild_in_a_subdirectory_layout() {
	need_real_wp || return 0
	mk_docroot r7 app/public
	run_tool my-theme; assert_rc 0
	rm -f "${OUTD}/my-theme.0.1.0.zip"
	run_tool my-theme --rebuild
	assert_rc 0
	assert_has "内容の指紋が、タグの記録と一致しました"
}

test_rebuild_with_dot_path() {
	need_real_wp || return 0
	mk_single r8
	run_tool solo-plugin; assert_rc 0
	rm -f "${OUTD}/solo-plugin.0.5.0.zip"
	LABEL="Git のルート"; run_tool solo-plugin --rebuild; assert_rc 0; assert_has "内容の指紋が、タグの記録と一致しました"
	mk_single r8b sub/dir
	run_tool solo-plugin; assert_rc 0
	rm -f "${OUTD}/solo-plugin.0.5.0.zip"
	LABEL="サブディレクトリ"; run_tool solo-plugin --rebuild; assert_rc 0; assert_has "内容の指紋が、タグの記録と一致しました"
}

tests_main "$@"
