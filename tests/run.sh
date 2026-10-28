#!/usr/bin/env bash
#
# テストの入口. tests/cases/*.sh を、1 ファイルずつ別プロセスで流して、結果をまとめる.
#
#   tests/run.sh                 すべて(shellcheck も含む)
#   tests/run.sh cli             ファイル名に 'cli' を含むケースだけ
#   tests/run.sh cli version     そのファイルの中で、テスト名に 'version' を含むものだけ
#
# 環境変数:
#   WRZM_BASH   ツールを動かす bash(既定 /bin/bash. macOS では 3.2 なので、3.2 互換の確認になる)
#   WRZM_TOOL   テストするツール(既定 bin/wp-release-zip-maker)
#
# 必要なもの: git 2.32 以上(GIT_CONFIG_GLOBAL)・unzip. Zip を実際に作るテストは、実物の `wp dist-archive` と zip が
# 無ければ SKIP になる. shellcheck が無ければ、その検査は SKIP になる.
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
FILE_FILTER="${1:-}"
TEST_FILTER="${2:-}"

total_fail=0
total_files=0

# ファイルごとの目安の秒数. 始める前に合計を表示し、時間がかかることを先に知らせるために使う.
# 2026-10-28 に、この Mac のサンドボックスの中で実測した値. 測り直したら直す(README の「開発・テスト」も).
# 時間の大半は、実物の WP-CLI で Zip を作る 40_zip・50_tag_rebuild・60_deploy_hint.
# 目安が無いファイル(新しく足したもの)は 0 を返す. 合計の表示で、目安の無いファイルがあることを添える.
estimate_seconds() {
	case "$1" in
		lint) echo 4 ;;
		10_cli) echo 1 ;;
		20_config) echo 3 ;;
		30_preflight) echo 14 ;;
		40_zip) echo 75 ;;
		50_tag_rebuild) echo 117 ;;
		60_deploy_hint) echo 70 ;;
		*) echo 0 ;;
	esac
}

# 秒数を「X 分 Y 秒」(60 秒未満は「Y 秒」)の形で標準出力へ出す.
format_seconds() {
	if [ "$1" -ge 60 ]; then
		printf '%d 分 %d 秒' $(($1 / 60)) $(($1 % 60))
	else
		printf '%d 秒' "$1"
	fi
}

# Git が GIT_CONFIG_GLOBAL に対応しているか(2.32 以上). 対応していないとテストが実行する人の設定に左右されるので、止める.
git_version="$(git --version | awk '{print $3}')"
git_major="${git_version%%.*}"
git_rest="${git_version#*.}"
git_minor="${git_rest%%.*}"
if [ "${git_major}" -lt 2 ] || { [ "${git_major}" -eq 2 ] && [ "${git_minor}" -lt 32 ]; }; then
	echo "git ${git_version} は古すぎます(GIT_CONFIG_GLOBAL に対応する 2.32 以上が必要です)." >&2
	exit 2
fi

# --- 流す対象を先に決める(目安の時間を、始める前に表示するため) ------------------------------
# lint は、絞り込みが無いときと 'lint' のときだけ. ケースは、ファイル名に FILE_FILTER を含むもの('lint' のときは無し).
run_lint=0
if [ -z "${FILE_FILTER}" ] || [ "${FILE_FILTER}" = "lint" ]; then
	run_lint=1
fi
CASES=()
if [ "${FILE_FILTER}" != "lint" ]; then
	for f in "${HERE}"/cases/*.sh; do
		name="$(basename "${f}" .sh)"
		if [ -n "${FILE_FILTER}" ] && [[ "${name}" != *"${FILE_FILTER}"* ]]; then
			continue
		fi
		CASES[${#CASES[@]}]="${f}"
	done
fi

# 絞り込みが何にも当たらなければ止める. 以前は「すべて成功(0 ファイル)」で 0 を返し、打ち間違いでも成功に見えた.
if [ "$((run_lint + ${#CASES[@]}))" -eq 0 ]; then
	echo "'${FILE_FILTER}' を名前に含むテストのファイルがありません(tests/cases/ を確かめてください)." >&2
	exit 2
fi

# 目安の合計と、目安の無いファイルの数.
est_total=0
est_missing=0
if [ "${run_lint}" -eq 1 ]; then
	est_total=$((est_total + $(estimate_seconds lint)))
fi
i=0
while [ "${i}" -lt "${#CASES[@]}" ]; do
	est="$(estimate_seconds "$(basename "${CASES[${i}]}" .sh)")"
	[ "${est}" -gt 0 ] || est_missing=$((est_missing + 1))
	est_total=$((est_total + est))
	i=$((i + 1))
done

# 始める前の表示: 対象のファイルの数と、目安の時間.
printf '対象: %d ファイル / 目安 約 %s(2026-10-28 の実測)' "$((run_lint + ${#CASES[@]}))" "$(format_seconds "${est_total}")"
[ "${est_missing}" -eq 0 ] || printf '. ほかに目安の無いファイルが %d 個' "${est_missing}"
[ -z "${TEST_FILTER}" ] || printf '. テスト名で絞っているので、実際はこれより短い'
printf '\n\n'

# --- 実行 ---------------------------------------------------------------------------------------

# 静的検査: ツールとテストのすべてのシェルスクリプトを shellcheck で検査する.
if [ "${run_lint}" -eq 1 ]; then
	total_files=$((total_files + 1))
	if command -v shellcheck >/dev/null 2>&1; then
		started="${SECONDS}"
		# -x -P SCRIPTDIR: tests/cases/*.sh が source する tests/lib.sh(スクリプトのあるディレクトリからの相対パス)も追う.
		if (cd "${REPO}" && shellcheck -x -P SCRIPTDIR bin/wp-release-zip-maker tests/run.sh tests/lib.sh tests/cases/*.sh); then
			echo "ok    lint: shellcheck($((SECONDS - started)) 秒)"
		else
			echo "FAIL  lint: shellcheck"
			total_fail=$((total_fail + 1))
		fi
	else
		echo "SKIP  lint: shellcheck(shellcheck が見つかりません)"
	fi
fi

# 各ファイルの集計行(かかった秒数つき)は、lib.sh の tests_main が出す.
i=0
while [ "${i}" -lt "${#CASES[@]}" ]; do
	f="${CASES[${i}]}"
	name="$(basename "${f}" .sh)"
	total_files=$((total_files + 1))
	est="$(estimate_seconds "${name}")"
	if [ "${est}" -gt 0 ]; then
		echo "=== ${name}(目安 約 $(format_seconds "${est}"))"
	else
		echo "=== ${name}"
	fi
	if ! "${WRZM_BASH:-/bin/bash}" "${f}" "${TEST_FILTER}"; then
		total_fail=$((total_fail + 1))
	fi
	i=$((i + 1))
done

echo
if [ "${total_fail}" -eq 0 ]; then
	echo "すべて成功(${total_files} ファイル・$(format_seconds "${SECONDS}"))."
	exit 0
fi
echo "失敗があります(${total_fail} / ${total_files} ファイル・$(format_seconds "${SECONDS}"))."
exit 1
