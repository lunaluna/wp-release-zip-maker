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

# Git が GIT_CONFIG_GLOBAL に対応しているか(2.32 以上). 対応していないとテストが実行する人の設定に左右されるので、止める.
git_version="$(git --version | awk '{print $3}')"
git_major="${git_version%%.*}"
git_rest="${git_version#*.}"
git_minor="${git_rest%%.*}"
if [ "${git_major}" -lt 2 ] || { [ "${git_major}" -eq 2 ] && [ "${git_minor}" -lt 32 ]; }; then
	echo "git ${git_version} は古すぎます(GIT_CONFIG_GLOBAL に対応する 2.32 以上が必要です)." >&2
	exit 2
fi

# 静的検査: ツールとテストのすべてのシェルスクリプトを shellcheck で検査する.
if [ -z "${FILE_FILTER}" ] || [ "${FILE_FILTER}" = "lint" ]; then
	total_files=$((total_files + 1))
	if command -v shellcheck >/dev/null 2>&1; then
		# -x -P SCRIPTDIR: tests/cases/*.sh が source する tests/lib.sh(スクリプトのあるディレクトリからの相対パス)も追う.
		if (cd "${REPO}" && shellcheck -x -P SCRIPTDIR bin/wp-release-zip-maker tests/run.sh tests/lib.sh tests/cases/*.sh); then
			echo "ok    lint: shellcheck"
		else
			echo "FAIL  lint: shellcheck"
			total_fail=$((total_fail + 1))
		fi
	else
		echo "SKIP  lint: shellcheck(shellcheck が見つかりません)"
	fi
fi

for f in "${HERE}"/cases/*.sh; do
	name="$(basename "${f}" .sh)"
	if [ -n "${FILE_FILTER}" ] && [ "${FILE_FILTER}" != "lint" ] && [[ "${name}" != *"${FILE_FILTER}"* ]]; then
		continue
	fi
	[ "${FILE_FILTER}" = "lint" ] && continue
	total_files=$((total_files + 1))
	echo "=== ${name}"
	if ! "${WRZM_BASH:-/bin/bash}" "${f}" "${TEST_FILTER}"; then
		total_fail=$((total_fail + 1))
	fi
done

echo
if [ "${total_fail}" -eq 0 ]; then
	echo "すべて成功(${total_files} ファイル)."
	exit 0
fi
echo "失敗があります(${total_fail} / ${total_files} ファイル)."
exit 1
