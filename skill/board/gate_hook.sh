#!/usr/bin/env bash
# Kiro PreToolUse 훅: 내 레인이 정지(hold/human 대기)면 도구 호출을 막는다. 0=통과, 2=차단.
# - 상황판 자체를 부르는 호출(board.sh read/wait/…)은 항상 통과 (안 그러면 대기도 못 한다)
# - 상황판 서버에 못 닿으면 통과 (fail-open: 서버가 죽었다고 개발이 멈추면 안 된다)
# - 결과를 20초 캐시해서 도구 호출마다 네트워크를 타지 않는다
input=$(cat 2>/dev/null || true)
# 커밋·푸시는 사람이 직접 한다 (board.sh 예외보다 먼저 검사: "git push && board.sh …" 우회 방지)
# 셸 명령 문자열만 본다(파일 내용에 "git commit"이 들어간 문서 쓰기를 막지 않게). JSON을 못 읽으면 입력 전체를 본다.
cmds=$(printf '%s' "$input" | python3 -c '
import json, sys
def walk(o, out):
    if isinstance(o, dict):
        for k, v in o.items():
            if isinstance(v, str) and k.lower() in ("command", "cmd", "script", "bash", "shell"): out.append(v)
            elif isinstance(v, list) and k.lower() in ("args", "argv", "command"): out.append(" ".join(map(str, v)))
            else: walk(v, out)
    elif isinstance(o, list):
        for v in o: walk(v, out)
out = []; walk(json.load(sys.stdin), out); print("\n".join(out))' 2>/dev/null) || cmds="$input"
if printf '%s' "$cmds" | grep -v 'git[[:space:]]\{1,\}stash[[:space:]]\{1,\}push' |
   grep -Eq '(^|[^[:alnum:]_./-])(git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+(commit|push)|gh[[:space:]]+pr[[:space:]]+(create|merge))([^[:alnum:]_-]|$)'; then
  echo "🚫 커밋·푸시는 사람이 직접 한다. 실행하지 말고 ①스테이징할 파일 목록 ②커밋 메시지에 적을 내용(무엇을·왜·영향 레인)만 채팅에 제안하라. 사람이 커밋하면 다음 작업으로 간다." >&2
  exit 2
fi
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
