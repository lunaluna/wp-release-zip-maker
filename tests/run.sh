#!/usr/bin/env bash
#
# テストの入口. tests/cases/*.sh を、1 ファイルずつ別プロセスで流して、結果をまとめる.
#
#   tests/run.sh                     速いテストだけ(shellcheck も含む). 実物の WP-CLI が要るテストは飛ばす
#   tests/run.sh --all               すべて(実物の WP-CLI で Zip を作るテストも. 約 2 分半)
#   tests/run.sh cli                 ファイル名に 'cli' を含むケースだけ
#   tests/run.sh cli version         そのファイルの中で、テスト名に 'version' を含むものだけ
#   tests/run.sh --all zip rebuild   絞り込みと --all は組み合わせられる(--all はどこに書いてもよい)
#   tests/run.sh --list              流さずに、ファイルごとの件数と目安の時間を一覧にする(絞り込みも効く)
#
# --all が無ければ、絞り込みの有無にかかわらず、実物の WP-CLI が要るテストは飛ばす(2026-10-28 のユーザーの決定).
# 全部を流すと約 2 分半かかるため. リリースの前(版を上げる前)には --all を必ず流す.
#
# 環境変数:
#   WRZM_BASH   ツールを動かす bash(既定 /bin/bash. macOS では 3.2 なので、3.2 互換の確認になる)
#   WRZM_TOOL   テストするツール(既定 bin/wp-release-zip-maker)
# 次の 2 つは run.sh が立てて、lib.sh の need_real_wp が読む(手で立てなくてよい):
#   WRZM_QUICK      1 なら、実物の WP-CLI が要るテストを飛ばす
#   WRZM_QUICK_LOG  飛ばしたテストを 1 行ずつ書くファイル(最後に件数を数える)
#
# 必要なもの: git 2.32 以上(GIT_CONFIG_GLOBAL)・unzip. Zip を実際に作るテストは、実物の `wp dist-archive` と zip が
# 無ければ SKIP になる. shellcheck が無ければ、その検査は SKIP になる.
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"

# --- 引数 ---------------------------------------------------------------------------------------
# オプション(--all・--list)はどこに書いてもよい. 残りの 1 つ目 = ファイル名の絞り込み・2 つ目 = テスト名の絞り込み.
RUN_ALL=0
WANT_LIST=0
FILE_FILTER=""
TEST_FILTER=""
npos=0
for arg in "$@"; do
	case "${arg}" in
		--all) RUN_ALL=1 ;;
		--list) WANT_LIST=1 ;;
		-h | --help)
			# このファイルの先頭のコメント(使い方)を出す.
			sed -n '3,/^# SPDX/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
			exit 0
			;;
		-*)
			echo "不明なオプション '${arg}'. tests/run.sh --help で使い方を確かめてください." >&2
			exit 2
			;;
		*)
			npos=$((npos + 1))
			case "${npos}" in
				1) FILE_FILTER="${arg}" ;;
				2) TEST_FILTER="${arg}" ;;
				*)
					echo "余分な引数です('${arg}'). 絞り込みは、ファイル名とテスト名の 2 つまでです." >&2
					exit 2
					;;
			esac
			;;
	esac
done

total_fail=0
total_files=0

# ファイルごとの目安の秒数. 始める前に合計を表示し、時間がかかることを先に知らせるために使う.
#   $1 = ファイルの名前(lint・10_cli など) / $2 = all(--all のとき)・quick(速いテストだけのとき)
# 2026-10-28 に、この Mac のサンドボックスの中で実測した値(--all は 1.1.0 のステップ 4 のあとで 2 分 34 秒. 30_preflight は 14〜19 秒で揺れる). 測り直したら直す(README の「開発・テスト」も).
# 時間の大半は、実物の WP-CLI で Zip を作る 40_zip・50_tag_rebuild・60_deploy_hint(--all のときだけ流す).
# 目安が無いファイル(新しく足したもの)は 0 を返す. 合計の表示で、目安の無いファイルがあることを添える.
estimate_seconds() {
	case "$1:$2" in
		lint:*) echo 3 ;;
		10_cli:*) echo 1 ;;
		20_config:*) echo 2 ;;
		30_preflight:*) echo 19 ;;
		40_zip:all) echo 41 ;;
		40_zip:quick) echo 2 ;;
		50_tag_rebuild:all) echo 59 ;;
		50_tag_rebuild:quick) echo 1 ;;
		60_deploy_hint:all) echo 26 ;;
		60_deploy_hint:quick) echo 1 ;;
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

# ケースファイルのテストの数(test_ で始まる関数の数).
count_tests() {
	grep -c '^test_[A-Za-z0-9_]*()' "$1"
}

# ケースファイルのテストのうち、実物の WP-CLI が要るもの(本体で need_real_wp を呼ぶもの)の数.
count_real_wp_tests() {
	awk '/^test_[A-Za-z0-9_]*\(\)/ { if (real) n++; real = 0 } /need_real_wp/ { real = 1 } END { if (real) n++; print n + 0 }' "$1"
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

# 目安の合計(今回の流し方・--all のとき)と、目安の無いファイルの数.
mode="quick"
[ "${RUN_ALL}" -eq 0 ] || mode="all"
est_total=0
est_all=0
est_missing=0
if [ "${run_lint}" -eq 1 ]; then
	est_total=$((est_total + $(estimate_seconds lint "${mode}")))
	est_all=$((est_all + $(estimate_seconds lint all)))
fi
i=0
while [ "${i}" -lt "${#CASES[@]}" ]; do
	name="$(basename "${CASES[${i}]}" .sh)"
	est="$(estimate_seconds "${name}" "${mode}")"
	[ "${est}" -gt 0 ] || est_missing=$((est_missing + 1))
	est_total=$((est_total + est))
	est_all=$((est_all + $(estimate_seconds "${name}" all)))
	i=$((i + 1))
done

# --- --list: 流さずに、ファイルごとの件数と目安の時間を一覧にする --------------------------------
if [ "${WANT_LIST}" -eq 1 ]; then
	# 列の見出しは、日本語だと桁がそろわないので英字にする. REAL_WP = 実物の WP-CLI が要るテストの数(--all のときだけ流す).
	printf '%-16s %6s %8s %9s %9s\n' FILE TESTS REAL_WP 'QUICK(s)' 'ALL(s)'
	if [ "${run_lint}" -eq 1 ]; then
		printf '%-16s %6s %8s %9s %9s\n' lint 1 0 "$(estimate_seconds lint quick)" "$(estimate_seconds lint all)"
	fi
	i=0
	while [ "${i}" -lt "${#CASES[@]}" ]; do
		f="${CASES[${i}]}"
		name="$(basename "${f}" .sh)"
		printf '%-16s %6s %8s %9s %9s\n' "${name}" "$(count_tests "${f}")" "$(count_real_wp_tests "${f}")" \
			"$(estimate_seconds "${name}" quick)" "$(estimate_seconds "${name}" all)"
		i=$((i + 1))
	done
	printf '\n目安は 2026-10-28 の実測(0 は目安なし). QUICK = 引数なし(速いテストだけ)・ALL = --all.\n'
	exit 0
fi

# 始める前の表示: 流し方・対象のファイルの数・目安の時間.
if [ "${RUN_ALL}" -eq 1 ]; then
	printf '流し方: すべて(--all. 実物の WP-CLI で Zip を作るテストも流す)\n'
else
	printf '流し方: 速いテストだけ(実物の WP-CLI が要るテストは飛ばす. すべてなら --all で 約 %s)\n' "$(format_seconds "${est_all}")"
	# 飛ばしたテストを数えるためのファイル. lib.sh の need_real_wp が 1 行ずつ書く.
	WRZM_QUICK_LOG="$(mktemp "${TMPDIR:-/tmp}/wrzm-quick.XXXXXX")" || exit 2
	trap 'rm -f -- "${WRZM_QUICK_LOG}"' EXIT
	export WRZM_QUICK=1 WRZM_QUICK_LOG
fi
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
	est="$(estimate_seconds "${name}" "${mode}")"
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
# 速いテストだけのときは、飛ばした数を必ず出す(重いテストを流さないまま「すべて成功」と読まれないように).
if [ "${RUN_ALL}" -eq 0 ]; then
	skipped="$(wc -l <"${WRZM_QUICK_LOG}" | tr -d ' ')"
	echo "実物の WP-CLI が要る ${skipped} 件を飛ばしました. すべてを流すなら tests/run.sh --all(目安 約 $(format_seconds "${est_all}")). リリースの前には必ず流してください."
fi
if [ "${total_fail}" -eq 0 ]; then
	echo "すべて成功(${total_files} ファイル・$(format_seconds "${SECONDS}"))."
	exit 0
fi
echo "失敗があります(${total_fail} / ${total_files} ファイル・$(format_seconds "${SECONDS}"))."
exit 1
