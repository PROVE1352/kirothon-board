#!/usr/bin/env bash
# Kiro AgentStop 훅: 에이전트 턴이 끝날 때 새 커밋이 있으면 상황판에 자동 보고한다.
# 사람이 직접 Kiro를 몰아서(프론트 등) Kiro가 done 보고를 잊어도 피드가 끊기지 않게 한다. 실패는 조용히 무시.
cat >/dev/null 2>&1 || true
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
head=$(git rev-parse --short HEAD 2>/dev/null) || exit 0
mark="$(git rev-parse --git-dir)/.board_last_reported"
[ "$(cat "$mark" 2>/dev/null)" = "$head" ] && exit 0
last=$(cat "$mark" 2>/dev/null || true)
n=1; [ -n "$last" ] && n=$(git rev-list --count "$last..HEAD" 2>/dev/null || echo 1)
msg="auto: 커밋 ${n}개, 최신 ${head} $(git log -1 --pretty=%s | cut -c1-120) [$(git diff --stat HEAD~1 2>/dev/null | tail -1 | sed 's/^ *//')]"
"$(dirname "$0")/board.sh" status "$msg" >/dev/null 2>&1 && printf '%s' "$head" > "$mark"
exit 0
