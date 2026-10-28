#!/usr/bin/env bash
#
# テストの入口. tests/cases/*.sh を、1 ファイルずつ別プロセスで流して、結果をまとめる.
#
#   tests/run.sh                     速いテストだけ(shellcheck も含む). 実物の WP-CLI が要るテストは飛ばす
#   tests/run.sh --all               すべて(実物の WP-CLI で Zip を作るテストも. 並列で約 1 分)
#   tests/run.sh --serial            ファイルを 1 つずつ順番に流す(既定は、lint とケースのファイルを同時に流す. --all の順番どおりは約 3 分 20 秒)
#   tests/run.sh cli                 ファイル名に 'cli' を含むケースだけ
#   tests/run.sh cli version         そのファイルの中で、テスト名に 'version' を含むものだけ
#   tests/run.sh --all zip rebuild   絞り込みと --all は組み合わせられる(--all はどこに書いてもよい)
#   tests/run.sh --list              流さずに、ファイルごとの件数と目安の時間を一覧にする(絞り込みも効く)
#
# --all が無ければ、絞り込みの有無にかかわらず、実物の WP-CLI が要るテストは飛ばす(2026-10-28 のユーザーの決定).
# リリースの前(版を上げる前)には --all を必ず流す.
#
# 並列(既定. 2026-10-28 のユーザーの決定): lint と、ケースの各ファイルを、別のプロセスで同時に起動する.
#   各プロセスの出力は、ファイルごとのログに貯め、ファイルの順に wait して、順に出す(出力が混ざらない. 長いファイルを待つ間は、あとのファイルの出力が出ない).
#   一時ディレクトリ・TMPDIR・GIT_CONFIG_GLOBAL は、ファイルごとに別(tests/lib.sh の setup_root). WRZM_QUICK_LOG も、ファイルごとに分ける.
#   実測(2026-10-28・CPU 10): 7 本同時で全体 62〜65 秒(順番どおりは 3 分 12 秒〜3 分 26 秒). 各ファイルの時間の延びは +4 秒以内. 失敗は 0(3 回).
#   --serial は、ファイルごとの時間を、ほかに邪魔されずに測りたいとき(目安の測り直し)や、並列で原因の分からない失敗が出たときの切り分けに使う.
#
# 環境変数:
#   WRZM_BASH   ツールを動かす bash(既定 /bin/bash. macOS では 3.2 なので、3.2 互換の確認になる)
#   WRZM_TOOL   テストするツール(既定 bin/wp-release-zip-maker)
# 次の 2 つは run.sh が立てて、lib.sh の need_real_wp が読む(手で立てなくてよい):
#   WRZM_QUICK      1 なら、実物の WP-CLI が要るテストを飛ばす
#   WRZM_QUICK_LOG  飛ばしたテストを 1 行ずつ書くファイル(最後に件数を数える. 並列のときは、ファイルごとに run.sh が別のファイルを渡す)
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
PARALLEL=1
FILE_FILTER=""
TEST_FILTER=""
npos=0
for arg in "$@"; do
	case "${arg}" in
		--all) RUN_ALL=1 ;;
		--list) WANT_LIST=1 ;;
		--serial) PARALLEL=0 ;;
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
# 2026-10-28 に、この Mac のサンドボックスの中で実測した値(1.2.0 のステップ 7. 順番どおりの --all の各ファイルは、ステップ 4・5 のあとの実測:
#   lint 3〜4・10_cli 0〜1・20_config 3・30_preflight 40〜41・40_zip 55〜62・50_tag_rebuild 62・60_deploy_hint 26〜31 秒. 合計は 3 分 12 秒〜3 分 26 秒).
# 測り直したら直す(README の「開発・テスト」も).
# 時間の大半は、実物の WP-CLI で Zip を作る 40_zip・50_tag_rebuild・60_deploy_hint(--all のときだけ流す).
# 速いテストだけ(quick)の値は、1.1.0 の実測のまま(1.2.0 で増えた分は未測定).
# 目安が無いファイル(新しく足したもの)は 0 を返す. 合計の表示で、目安の無いファイルがあることを添える.
estimate_seconds() {
	case "$1:$2" in
		lint:*) echo 4 ;;
		10_cli:*) echo 1 ;;
		20_config:*) echo 3 ;;
		30_preflight:*) echo 41 ;;
		40_zip:all) echo 60 ;;
		40_zip:quick) echo 2 ;;
		50_tag_rebuild:all) echo 62 ;;
		50_tag_rebuild:quick) echo 1 ;;
		60_deploy_hint:all) echo 28 ;;
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
# 並列のときの目安 = 最も長いファイルの時間(同時に流すため). 順番どおり(--serial)のときは合計.
add_estimate() {
	# $1 = 今回の流し方での秒数 / $2 = --all での秒数
	if [ "${PARALLEL}" -eq 1 ]; then
		[ "$1" -le "${est_total}" ] || est_total="$1"
		[ "$2" -le "${est_all}" ] || est_all="$2"
	else
		est_total=$((est_total + $1))
		est_all=$((est_all + $2))
	fi
}
if [ "${run_lint}" -eq 1 ]; then
	add_estimate "$(estimate_seconds lint "${mode}")" "$(estimate_seconds lint all)"
fi
i=0
while [ "${i}" -lt "${#CASES[@]}" ]; do
	name="$(basename "${CASES[${i}]}" .sh)"
	est="$(estimate_seconds "${name}" "${mode}")"
	[ "${est}" -gt 0 ] || est_missing=$((est_missing + 1))
	add_estimate "${est}" "$(estimate_seconds "${name}" all)"
	i=$((i + 1))
done

# 対象全体の目安を出す. $1 = max(並列の目安: 最も長いファイル)か sum(順番どおりの目安: 合計) / $2 = quick か all.
est_agg() {
	local agg="$1" m="$2" v total=0 n
	if [ "${run_lint}" -eq 1 ]; then
		total="$(estimate_seconds lint "${m}")"
	fi
	for n in "${CASES[@]+"${CASES[@]}"}"; do
		v="$(estimate_seconds "$(basename "${n}" .sh)" "${m}")"
		if [ "${agg}" = max ]; then
			[ "${v}" -le "${total}" ] || total="${v}"
		else
			total=$((total + v))
		fi
	done
	echo "${total}"
}

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
	if [ "${PARALLEL}" -eq 1 ]; then
		printf '既定は並列なので、全体の目安は最も長いファイルの時間: 引数なし 約 %s・--all 約 %s(順番どおりなら --serial で、各ファイルの合計).\n' \
			"$(format_seconds "$(est_agg max quick)")" "$(format_seconds "$(est_agg max all)")"
	else
		printf '順番どおり(--serial)の全体の目安は、各ファイルの合計: 引数なし 約 %s・--all 約 %s.\n' \
			"$(format_seconds "$(est_agg sum quick)")" "$(format_seconds "$(est_agg sum all)")"
	fi
	exit 0
fi

# 始める前の表示: 流し方・対象のファイルの数・目安の時間.
if [ "${RUN_ALL}" -eq 1 ]; then
	printf '流し方: すべて(--all. 実物の WP-CLI で Zip を作るテストも流す)\n'
else
	printf '流し方: 速いテストだけ(実物の WP-CLI が要るテストは飛ばす. すべてなら --all で 約 %s)\n' "$(format_seconds "${est_all}")"
	# 飛ばしたテストを数えるためのファイル. lib.sh の need_real_wp が 1 行ずつ書く.
	# 並列のときは、ファイルごとに別のログを使う(下の RUN_DIR の quick.<ファイル名>. 1 つのファイルに、複数のプロセスが書かないように).
	WRZM_QUICK_LOG="$(mktemp "${TMPDIR:-/tmp}/wrzm-quick.XXXXXX")" || exit 2
	trap 'rm -f -- "${WRZM_QUICK_LOG}"' EXIT
	export WRZM_QUICK=1 WRZM_QUICK_LOG
fi
# 並列のときの、ファイルごとのログ置き場(出力・終了コード・飛ばした数). 終了時に消す.
RUN_DIR=""
if [ "${PARALLEL}" -eq 1 ]; then
	RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wrzm-run.XXXXXX")" || exit 2
	trap 'rm -rf -- "${RUN_DIR}"; [ -z "${WRZM_QUICK_LOG:-}" ] || rm -f -- "${WRZM_QUICK_LOG}"' EXIT
fi
[ "${PARALLEL}" -eq 0 ] || printf '並列で流します(lint とケースのファイルを同時に起動し、ファイルの順に結果を出します. 順番どおりなら --serial)\n'
printf '対象: %d ファイル / 目安 約 %s(2026-10-28 の実測)' "$((run_lint + ${#CASES[@]}))" "$(format_seconds "${est_total}")"
[ "${est_missing}" -eq 0 ] || printf '. ほかに目安の無いファイルが %d 個' "${est_missing}"
[ -z "${TEST_FILTER}" ] || printf '. テスト名で絞っているので、実際はこれより短い'
printf '\n\n'

# --- 実行 ---------------------------------------------------------------------------------------

# 静的検査: ツールとテストのすべてのシェルスクリプトを shellcheck で検査する. 結果を表示し、失敗なら 1 を返す(無い場合は SKIP で 0).
run_lint_job() {
	local started="${SECONDS}"
	if command -v shellcheck >/dev/null 2>&1; then
		# -x -P SCRIPTDIR: tests/cases/*.sh が source する tests/lib.sh(スクリプトのあるディレクトリからの相対パス)も追う.
		if (cd "${REPO}" && shellcheck -x -P SCRIPTDIR bin/wp-release-zip-maker tests/run.sh tests/lib.sh tests/cases/*.sh); then
			echo "ok    lint: shellcheck($((SECONDS - started)) 秒)"
		else
			echo "FAIL  lint: shellcheck"
			return 1
		fi
	else
		echo "SKIP  lint: shellcheck(shellcheck が見つかりません)"
	fi
	return 0
}

# ケースのファイルの見出しの行を出す. $1 = ファイル名(10_cli など)
print_case_header() {
	local est
	est="$(estimate_seconds "$1" "${mode}")"
	if [ "${est}" -gt 0 ]; then
		echo "=== $1(目安 約 $(format_seconds "${est}"))"
	else
		echo "=== $1"
	fi
}

# 各ファイルの集計行(かかった秒数つき)は、lib.sh の tests_main が出す.
if [ "${PARALLEL}" -eq 1 ]; then
	# 並列: 全部を先に起動する(7 つ程度なので、一度に起動してよい). bash 3.2 に wait -n が無いので、起動した順に wait する.
	# 各プロセスの標準出力・標準エラーは、RUN_DIR/<名前>.out に貯める. 終了コードは wait の戻りで取る.
	LINT_PID=""
	if [ "${run_lint}" -eq 1 ]; then
		run_lint_job >"${RUN_DIR}/lint.out" 2>&1 &
		LINT_PID=$!
	fi
	CASE_PIDS=()
	i=0
	while [ "${i}" -lt "${#CASES[@]}" ]; do
		f="${CASES[${i}]}"
		name="$(basename "${f}" .sh)"
		if [ "${RUN_ALL}" -eq 0 ]; then
			WRZM_QUICK_LOG="${RUN_DIR}/quick.${name}" "${WRZM_BASH:-/bin/bash}" "${f}" "${TEST_FILTER}" >"${RUN_DIR}/${name}.out" 2>&1 &
		else
			"${WRZM_BASH:-/bin/bash}" "${f}" "${TEST_FILTER}" >"${RUN_DIR}/${name}.out" 2>&1 &
		fi
		CASE_PIDS[i]=$!
		i=$((i + 1))
	done
	# 起動した順に待って、順に出す.
	if [ -n "${LINT_PID}" ]; then
		total_files=$((total_files + 1))
		wait "${LINT_PID}" || total_fail=$((total_fail + 1))
		cat "${RUN_DIR}/lint.out"
	fi
	i=0
	while [ "${i}" -lt "${#CASES[@]}" ]; do
		name="$(basename "${CASES[${i}]}" .sh)"
		total_files=$((total_files + 1))
		print_case_header "${name}"
		wait "${CASE_PIDS[${i}]}" || total_fail=$((total_fail + 1))
		cat "${RUN_DIR}/${name}.out"
		i=$((i + 1))
	done
else
	if [ "${run_lint}" -eq 1 ]; then
		total_files=$((total_files + 1))
		run_lint_job || total_fail=$((total_fail + 1))
	fi
	i=0
	while [ "${i}" -lt "${#CASES[@]}" ]; do
		f="${CASES[${i}]}"
		name="$(basename "${f}" .sh)"
		total_files=$((total_files + 1))
		print_case_header "${name}"
		if ! "${WRZM_BASH:-/bin/bash}" "${f}" "${TEST_FILTER}"; then
			total_fail=$((total_fail + 1))
		fi
		i=$((i + 1))
	done
fi

echo
# 速いテストだけのときは、飛ばした数を必ず出す(重いテストを流さないまま「すべて成功」と読まれないように).
if [ "${RUN_ALL}" -eq 0 ]; then
	if [ "${PARALLEL}" -eq 1 ]; then
		# ファイルごとのログを合わせて数える(quick.* が 1 つも無ければ 0).
		skipped="$(cat "${RUN_DIR}"/quick.* 2>/dev/null | wc -l | tr -d ' ')"
	else
		skipped="$(wc -l <"${WRZM_QUICK_LOG}" | tr -d ' ')"
	fi
	echo "実物の WP-CLI が要る ${skipped} 件を飛ばしました. すべてを流すなら tests/run.sh --all(目安 約 $(format_seconds "${est_all}")). リリースの前には必ず流してください."
fi
if [ "${total_fail}" -eq 0 ]; then
	echo "すべて成功(${total_files} ファイル・$(format_seconds "${SECONDS}"))."
	exit 0
fi
echo "失敗があります(${total_fail} / ${total_files} ファイル・$(format_seconds "${SECONDS}"))."
exit 1
