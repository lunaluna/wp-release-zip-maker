#!/usr/bin/env bash
#
# テストの共通部品. 各ケースファイル(tests/cases/*.sh)が source する.
#
# 方針:
#   - bash だけで書く(外部のテストツールを入れない). macOS 標準の bash 3.2 でも動く書き方にする.
#   - テストは一時ディレクトリの中だけで動く. Git の設定(GIT_CONFIG_GLOBAL)と TMPDIR をテスト用に差し替え、
#     実行する人の環境(コミッターの設定・一時ディレクトリ)に結果が左右されないようにする.
#     GIT_CONFIG_GLOBAL は Git 2.32 以上が要る.
#   - 事前の確認のテストは、偽の wp(dist-archive --help にだけ答える)で動かす. Zip を実際に作るテストは、
#     実物の `wp dist-archive` が無ければ SKIP にする.
#
# 使い方(ケースファイルの形):
#   source "$(dirname "$0")/../lib.sh"
#   test_何かをする() { ... run_tool ... ; assert_rc 0; assert_has '...'; }
#   tests_main "$@"
#
# SPDX-License-Identifier: GPL-2.0-or-later

# shellcheck disable=SC2034  # FX・BASE・OUTD・P・TH・CUR_NAME などは、これを source する tests/cases/*.sh が使う
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
# テストするツール(WRZM_TOOL で差し替えられる). 既定はこのリポジトリの bin/wp-release-zip-maker.
TOOL="${WRZM_TOOL:-${REPO_DIR}/bin/wp-release-zip-maker}"
# ツールを動かす bash. 既定は /bin/bash(macOS では 3.2 なので、bash 3.2 互換の確認になる).
TOOL_BASH="${WRZM_BASH:-/bin/bash}"

# --- 集計 ---------------------------------------------------------------------------------------
N_PASS=0
N_FAIL=0
N_SKIP=0
CUR_NAME=""
CUR_FAIL=0
CUR_SKIP=""
LABEL=""   # assert のメッセージに添える、場面の名前(1 つのテストの中で複数の場面を流すとき)

# テストの結果の出力を溜める一時ファイル(失敗したときだけ中身を出す).
BUF=""

# 失敗を記録する. メッセージは、失敗したテストのあとにまとめて出る.
fail() {
	CUR_FAIL=$((CUR_FAIL + 1))
	printf '    FAIL%s: %s\n' "${LABEL:+ [${LABEL}]}" "$*"
}

# テストを飛ばす(例: 実物の wp dist-archive が無い). 呼び出し側は return する.
skip() {
	CUR_SKIP="$1"
}

# --- 実行環境(一時ディレクトリ・Git の設定) -----------------------------------------------------
TEST_ROOT=""

# テスト用の一時ディレクトリと、隔離した環境を用意する. 終了時に消す.
setup_root() {
	TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/wrzm-test.XXXXXX")"
	TEST_ROOT="$(cd "${TEST_ROOT}" && pwd -P)"
	trap cleanup_root EXIT
	mkdir -p "${TEST_ROOT}/tmp"
	# ツールが作る一時ディレクトリ(wp-release-zip-maker.XXXXXX)の取り残しを、テストごとに数えるため、TMPDIR を分ける.
	export TMPDIR="${TEST_ROOT}/tmp"
	# コミッターを、テスト用の設定ファイルで決める(実行する人の ~/.gitconfig に依存しない).
	printf '[user]\n\tname = Test User\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n' > "${TEST_ROOT}/gitconfig"
	export GIT_CONFIG_GLOBAL="${TEST_ROOT}/gitconfig"
	export GIT_CONFIG_NOSYSTEM=1
	export GIT_TERMINAL_PROMPT=0
	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
}

cleanup_root() {
	if [ -n "${TEST_ROOT}" ] && [ -d "${TEST_ROOT}" ]; then
		rm -rf -- "${TEST_ROOT}"
	fi
}

# ツールが取り残した一時ディレクトリの数.
leftover_tmp_count() {
	find "${TMPDIR}" -maxdepth 1 -name 'wp-release-zip-maker.*' 2>/dev/null | wc -l | tr -d ' '
}

# --- ツールの実行 -------------------------------------------------------------------------------
OUT=""
RC=0

# ツールを、カレントディレクトリで実行する. 標準出力と標準エラーを OUT に、終了コードを RC に入れる.
run_tool() {
	OUT="$("${TOOL_BASH}" "${TOOL}" "$@" 2>&1)"
	RC=$?
}

# 環境変数つきで実行する. 書式: run_tool_env VAR=値 ... -- 引数...
run_tool_env() {
	local envs=()
	while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
		envs[${#envs[@]}]="$1"
		shift
	done
	shift
	# bash 3.2 は、空の配列を "${envs[@]}" と展開すると set -u で落ちる. ${envs[@]+...} の形で避ける.
	OUT="$(env ${envs[@]+"${envs[@]}"} "${TOOL_BASH}" "${TOOL}" "$@" 2>&1)"
	RC=$?
}

# --- アサーション -------------------------------------------------------------------------------

# 出力を、失敗メッセージに添える形に整える(長いので先頭の十数行だけ).
show_out() {
	printf '%s\n' "${OUT}" | head -n 14 | sed 's/^/        | /'
}

assert_rc() {
	if [ "${RC}" -ne "$1" ]; then
		fail "終了コード: 期待 $1 / 実際 ${RC}"
		show_out
	fi
}

# 出力に文字列が含まれる(固定文字列で探す).
assert_has() {
	if ! printf '%s' "${OUT}" | grep -aqF -- "$1"; then
		fail "出力に '$1' がありません"
		show_out
	fi
}

# 出力に文字列が含まれない.
assert_lacks() {
	if printf '%s' "${OUT}" | grep -aqF -- "$1"; then
		fail "出力に '$1' が含まれています"
		show_out
	fi
}

assert_eq() {
	if [ "$1" != "$2" ]; then
		fail "${3:-値}: 期待 '$1' / 実際 '$2'"
	fi
}

assert_file() {
	[ -e "$1" ] || fail "ファイルがありません: ${1#"${TEST_ROOT}"/}"
}

assert_no_file() {
	[ ! -e "$1" ] || fail "ファイルが残っています: ${1#"${TEST_ROOT}"/}"
}

# --- Git・Zip の道具 ----------------------------------------------------------------------------

# 全部をステージして、コミットする. 引数 = メッセージ.
gcommit() {
	git add -A && git commit -q -m "$1"
}

# Zip の中のファイル名を 1 行ずつ出す. ASCII 以外のバイトは '?' にそろえる(unzip の出力が環境で崩れるため).
zip_names() {
	unzip -Z1 "$1" 2>/dev/null | LC_ALL=C tr -c '[:print:]\n' '?'
}

# Zip の中に、その名前のファイルがあるか(完全一致).
zip_has() {
	zip_names "$1" | grep -aqxF -- "$2"
}

# Zip の中のファイルの中身を出す. 引数 = Zip・ファイル名.
zip_cat() {
	unzip -p "$1" "$2" 2>/dev/null
}

# ファイルの SHA-256(64 桁の 16 進数). ツールの sha256_of と似た処理だが、意図して実装に頼らず、テスト側で独立に計算する(期待値の元を、実装と分けるため).
sha256_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		sha256sum "$1" | cut -d' ' -f1
	fi
}

# 実物の `wp dist-archive` があるか(Zip を実際に作るテストの前提).
have_dist_archive() {
	command -v wp >/dev/null 2>&1 && wp dist-archive --help >/dev/null 2>&1 && command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1
}

# 実物の wp dist-archive が無ければ、そのテストを飛ばす(SKIP にする). 使い方(テストの先頭): need_real_wp || return 0
need_real_wp() {
	if have_dist_archive; then
		return 0
	fi
	skip "実物の wp dist-archive・zip・unzip が無い"
	return 1
}

# 偽の wp を作る. dist-archive --help には成功で答え、それ以外は第 2 引数のシェルのコード($@ が使える)を実行する.
#   $1 = 名前 / $2 = dist-archive の呼び出しのときに実行するコード. 出力: 偽の wp のパス.
# shellcheck disable=SC2016  # 偽の wp のスクリプトの中で評価する $1・$2 は、ここでは展開しない(シングルクォートのまま書き出す)
make_fake_wp() {
	local path="${TEST_ROOT}/fake-$1"
	printf '#!/bin/sh\nif [ "$1" = dist-archive ] && [ "$2" = "--help" ]; then exit 0; fi\n%s\n' "$2" > "${path}"
	chmod +x "${path}"
	printf '%s' "${path}"
}

# --- 見本のリポジトリ ---------------------------------------------------------------------------
FX=""     # リポジトリのルート
BASE=""   # 設定ファイル(.wp-release)のある場所(ルートの下のサブディレクトリのこともある)
OUTD=""   # Zip の出力先(リポジトリの外)
P="wp-content/plugins/my-plugin"
TH="wp-content/themes/my-theme"

# docroot 型の見本を作り、カレントを設定ファイルの場所にする. コミット済み・ブランチは main.
#   $1 = 名前 / $2 = 設定ファイルを置くサブディレクトリ(省略すると Git のルート)
# 中身:
#   plugin my-plugin : 版 1.2.3('my main.php'. 空白入りの名前). Plugin Name の無い a-helper.php(Version: 9.9.9)も置く
#   theme  my-theme  : 版 0.1.0
#   dir    landing   : lp ディレクトリ・版 2.0.0
#   dir    lpx       : VERSION を .distignore で除く(Zip に VERSION が入らない)
#   dir    nodist    : .distignore なし
#   check            : プラグインとテーマの package.json の version
mk_docroot() {
	FX="${TEST_ROOT}/$1"
	BASE="${FX}${2:+/$2}"
	OUTD="${TEST_ROOT}/out-$1"
	mkdir -p "${BASE}" && cd "${FX}" && git init -q -b main && cd "${BASE}" || return 1
	mkdir -p "${P}/src" "${P}/assets" "${TH}" lp lpx nodist
	printf '<?php\n// Version: 9.9.9 (Plugin Name が無いので読まない)\n' > "${P}/a-helper.php"
	printf '<?php\n/**\n * Plugin Name: My Plugin\n * Version: 1.2.3\n */\n' > "${P}/my main.php"
	printf '{\n  "version": "1.2.3"\n}\n' > "${P}/package.json"
	echo 1 > "${P}/src/a.js"
	echo 1 > "${P}/assets/app.js"
	printf '/src\npackage.json\n.distignore\nnode_modules\n' > "${P}/.distignore"
	printf '/*\nTheme Name: T\nVersion: 0.1.0\n*/\n' > "${TH}/style.css"
	printf '{\n  "version": "0.1.0"\n}\n' > "${TH}/package.json"
	printf '.distignore\npackage.json\n' > "${TH}/.distignore"
	printf '2.0.0\n' > lp/VERSION
	echo '<h1>lp</h1>' > lp/index.html
	printf '.distignore\n' > lp/.distignore
	printf '5.0.0\n' > lpx/VERSION
	echo x > lpx/a.html
	printf 'VERSION\n.distignore\n' > lpx/.distignore
	printf '1.0.0\n' > nodist/VERSION
	printf 'node_modules/\nlocal.txt\n' > .gitignore
	cat > .wp-release <<EOF
tag_format = {slug}/{version}
output     = ${OUTD}
plugin ${P}
theme  ${TH}
dir    lp      landing
dir    lpx
dir    nodist
check  ${P}/package.json:"version"
check  ${TH}/package.json:"version"
EOF
	gcommit "init"
}

# 設定ファイルを書き換えてコミットする. 引数 = 設定の本文(output は OUTD に置き換える必要が無いよう、呼び出し側が書く).
set_config() {
	printf '%s\n' "$1" > "${BASE}/.wp-release"
	gcommit "config"
}

# プラグインの版を上げてコミットする(my main.php と package.json). 引数 = 新しい版.
bump_plugin() {
	local f="${P}/my main.php"
	sed -i.bak "s/Version: [0-9.]*$/Version: $1/" "${f}" && rm -f "${f}.bak"
	sed -i.bak "s/\"version\": \"[0-9.]*\"/\"version\": \"$1\"/" "${P}/package.json" && rm -f "${P}/package.json.bak"
	gcommit "plugin $1"
}

# dir(lp)の版を上げてコミットする. 引数 = 新しい版. 前の版にだけあった removed-later.txt は、初回で消える.
bump_lp() {
	printf '%s\n' "$1" > lp/VERSION
	echo "<h1>lp $1</h1>" > lp/index.html
	gcommit "lp $1"
}

# プラグイン 1 つ型(パス '.')の見本を作る. カレントを設定ファイルの場所にする.
#   $1 = 名前 / $2 = 設定ファイルを置くサブディレクトリ(省略すると Git のルート)
mk_single() {
	FX="${TEST_ROOT}/$1"
	BASE="${FX}${2:+/$2}"
	OUTD="${TEST_ROOT}/out-$1"
	mkdir -p "${BASE}" && cd "${FX}" && git init -q -b main && cd "${BASE}" || return 1
	printf '<?php\n/*\nPlugin Name: Solo\nVersion: 0.5.0\n*/\n' > solo-main.php
	echo 1 > inc.php
	printf '.wp-release\n.distignore\n' > .distignore
	printf 'output = %s\nplugin . solo-plugin\n' "${OUTD}" > .wp-release
	gcommit "init"
}

# --- 実行 ---------------------------------------------------------------------------------------

# このファイルの test_ で始まる関数を、すべて(または引数で絞った名前だけ)実行して、結果を出す. 失敗があれば 1 で終わる.
tests_main() {
	local filter="${1:-}" fn
	setup_root
	BUF="${TEST_ROOT}/buf.txt"
	for fn in $(compgen -A function test_); do
		if [ -n "${filter}" ] && [[ "${fn}" != *"${filter}"* ]]; then
			continue
		fi
		CUR_NAME="${fn}"
		CUR_FAIL=0
		CUR_SKIP=""
		LABEL=""
		# 各テストは、カレントを一時ディレクトリに置いて始める(前のテストのカレントを引きずらない).
		cd "${TEST_ROOT}" || exit 1
		"${fn}" >"${BUF}" 2>&1
		if [ -n "${CUR_SKIP}" ]; then
			N_SKIP=$((N_SKIP + 1))
			printf 'SKIP  %s  (%s)\n' "${fn}" "${CUR_SKIP}"
		elif [ "${CUR_FAIL}" -eq 0 ]; then
			N_PASS=$((N_PASS + 1))
			printf 'ok    %s\n' "${fn}"
		else
			N_FAIL=$((N_FAIL + 1))
			printf 'FAIL  %s\n' "${fn}"
			cat "${BUF}"
		fi
	done
	cd "${TEST_ROOT}" || exit 1
	printf -- '--- %s: ok %s / FAIL %s / SKIP %s\n' "$(basename "$0")" "${N_PASS}" "${N_FAIL}" "${N_SKIP}"
	[ "${N_FAIL}" -eq 0 ]
}
