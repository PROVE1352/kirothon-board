#!/usr/bin/env bash
# Kiro PreToolUse 훅: 내 레인이 정지(hold/human 대기)면 도구 호출을 막는다. 0=통과, 2=차단.
# - 상황판 자체를 부르는 호출(board.sh read/wait/…)은 항상 통과 (안 그러면 대기도 못 한다)
# - 상황판 서버에 못 닿으면 통과 (fail-open: 서버가 죽었다고 개발이 멈추면 안 된다)
# - 결과를 20초 캐시해서 도구 호출마다 네트워크를 타지 않는다
input=$(cat 2>/dev/null || true)
case "$input" in *board.sh*|*adviser/ask.sh*) exit 0 ;; esac
cache="${TMPDIR:-/tmp}/.board_gate_$(id -u)"
now=$(date +%s)
if [ -f "$cache" ] && [ $(( now - $(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache") )) -lt 20 ]; then
  g=$(cat "$cache")
else
  g=$("$(dirname "$0")/board.sh" gate 2>/dev/null) || true
  [ -n "$g" ] || exit 0
  printf '%s' "$g" > "$cache"
fi
case "$g" in
  hold*) echo "🛑 상황판 정지 중: $g — 쓰기·실행을 멈추고 ~/.kiro/skills/board/board.sh wait 를 실행해 풀릴 때까지 기다려라." >&2; exit 2 ;;
  *) exit 0 ;;
esac
