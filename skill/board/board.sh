#!/usr/bin/env bash
# kirothon-board 클라이언트. 설정: ~/.kirothon-board.env 에 BOARD_URL, BOARD_TOKEN, BOARD_LANE
#   board.sh read                     상황판 + 내 레인에 온 지시
#   board.sh status "한 일 / 다음"     진행 보고
#   board.sh done "끝낸 것"            태스크 완료
#   board.sh blocked "막힌 것"         막힘 (오케스트라가 봄)
#   board.sh ask "질문"                다른 레인/오케스트라에게 질문
#   board.sh human "결정할 것 A/B"     사람 판단 필요 → 내 레인 정지, 팀장 맥에 알림. 이어서 wait
#   board.sh gate                     go면 exit 0, 정지 상태면 exit 3 (훅용)
#   board.sh wait                     풀릴 때까지 15초 간격 대기 (최대 30분)
#   board.sh idle                     할 일이 떨어졌을 때: 내 레인 앞으로 새 지시가 올 때까지 대기 (최대 10분, 없으면 다시 실행)
#   board.sh order <lane|all> "지시"   (오케스트라 전용) human 정지도 풀림
#   board.sh hold <lane|all> "사유"    (오케스트라 전용) 정지
#   board.sh release <lane|all> ["메모"] (오케스트라 전용) 재개
#   board.sh watch                    (팀장 맥) human/blocked 오면 macOS 알림
#   board.sh events [since_id]         JSON 원본
#   board.sh doctor [프로젝트 폴더]   설치 점검 (스킬·토큰·IP·오토모드·프로젝트 훅/steering)
#   board.sh ip                       서버가 보는 내 공인 IP (403 나면 이걸 팀장에게 전달)
#   board.sh allow <ip|cidr> [메모] / deny <ip|cidr> / allowed   (팀장 전용) IP allowlist
set -euo pipefail
# 환경변수가 이미 있으면 그쪽이 이긴다 (파일은 기본값)
if [ -f "$HOME/.kirothon-board.env" ]; then
  while IFS='=' read -r k v; do
    case "$k" in BOARD_URL|BOARD_TOKEN|BOARD_LANE) [ -n "${!k:-}" ] || export "$k=$v" ;; esac
  done < "$HOME/.kirothon-board.env"
fi
: "${BOARD_URL:?~/.kirothon-board.env 에 BOARD_URL 필요}" "${BOARD_TOKEN:?BOARD_TOKEN 필요}" "${BOARD_LANE:?BOARD_LANE 필요}"
AUTH="Authorization: Bearer $BOARD_TOKEN"
CURL=(curl -sS --max-time 10 -H "$AUTH")

post() { # kind text [to]
  python3 - "$BOARD_LANE" "$@" <<'PY' | "${CURL[@]}" -X POST -H 'Content-Type: application/json' --data-binary @- "$BOARD_URL/post"
import json, sys
lane, kind, text = sys.argv[1:4]
d = {"lane": lane, "kind": kind, "text": text}
if len(sys.argv) > 4: d["to"] = sys.argv[4]
print(json.dumps(d, ensure_ascii=False))
PY
}

cmd="${1:-read}"; shift || true
case "$cmd" in
  doctor) ok() { echo "✅ $1"; }; no() { echo "❌ $1"; bad=1; }; bad=0; D="$HOME/.kiro/skills/board"
          for f in SKILL.md board.sh gate_hook.sh auto_report.sh; do [ -e "$D/$f" ] || { no "스킬 파일 없음: $D/$f → ./setup.sh 다시"; }; done
          [ -x "$D/gate_hook.sh" ] && [ -x "$D/auto_report.sh" ] && ok "board 스킬 설치됨 ($D)"
          ok "내 레인: $BOARD_LANE"
          g=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$BOARD_URL/gate?lane=$BOARD_LANE" || true)
          case "$g" in 200) ok "상황판 연결 (토큰·IP 통과)" ;; 403) no "IP 미등록 → 이 IP를 팀장에게: $(curl -sS --max-time 10 "$BOARD_URL/ip")" ;;
            401) no "토큰 틀림 → ./setup.sh <레인> <토큰> 다시" ;; *) no "상황판 서버에 못 닿음 (HTTP $g)" ;; esac
          grep -q 'git commit' "$HOME/.kiro/settings/permissions.yaml" 2>/dev/null && ok "오토모드 + 커밋/푸시 차단 (permissions.yaml)" || no "permissions.yaml 에 커밋 차단 없음 → ./setup.sh 다시"
          r=$(printf '{"command":"git commit -m x"}' | "$D/gate_hook.sh" 2>/dev/null; echo $?); [ "$r" = 2 ] && ok "훅 스크립트가 git commit 을 막음" || no "훅 스크립트 이상 (exit $r)"
          if [ -n "${1:-}" ]; then
            [ -f "$1/.kiro/hooks/board-gate.json" ] && ok "프로젝트 훅: $1/.kiro/hooks/board-gate.json" || no "프로젝트 훅 없음 → ./setup.sh <레인> <토큰> $1"
            [ -f "$1/.kiro/steering/board.md" ] && ok "프로젝트 steering: $1/.kiro/steering/board.md" || no "프로젝트 steering 없음 → ./setup.sh <레인> <토큰> $1"
          else echo "ℹ️  프로젝트 훅·steering 은 내일 저장소 받은 뒤: board.sh doctor <프로젝트 폴더>"; fi
          [ "$bad" = 0 ] && echo "→ 전부 정상. Kiro에 '상황판 읽어' 를 쳐서 마지막 확인" || exit 1 ;;
  ip)     curl -sS --max-time 10 "$BOARD_URL/ip" ;;
  allowed) "${CURL[@]}" "$BOARD_URL/allow" ;;
  allow|deny) python3 -c 'import json,sys; print(json.dumps({"ip": sys.argv[1], "memo": sys.argv[2]}))' "${1:?ip 필요}" "${2:-}" |
            "${CURL[@]}" -X POST -H 'Content-Type: application/json' --data-binary @- "$BOARD_URL/$cmd" ;;
  read)   "${CURL[@]}" "$BOARD_URL/board?lane=$BOARD_LANE" ;;
  events) "${CURL[@]}" "$BOARD_URL/events?since=${1:-0}" ;;
  status|done|blocked|ask|note|human) post "$cmd" "${1:?내용 필요}" ;;
  order|hold) post "$cmd" "${2:?내용 필요}" "${1:?대상 레인 필요}" ;;
  release) post release "${2:-재개}" "${1:?대상 레인 필요}" ;;
  gate)   g=$("${CURL[@]}" "$BOARD_URL/gate?lane=$BOARD_LANE"); echo "$g"; [ "${g%% *}" = go ] || exit 3 ;;
  wait)   for _ in $(seq 120); do
            g=$("${CURL[@]}" "$BOARD_URL/gate?lane=$BOARD_LANE" || echo "hold (네트워크 오류)")
            [ "${g%% *}" = go ] && { echo "go — 재개. board.sh read 로 지시 확인"; exit 0; }
            sleep 15
          done; echo "30분째 정지: $g"; exit 3 ;;
  idle)   since=$("${CURL[@]}" "$BOARD_URL/events" | python3 -c 'import json,sys; e=json.load(sys.stdin); print(e[-1]["id"] if e else 0)')
          for _ in $(seq 40); do
            hit=$("${CURL[@]}" "$BOARD_URL/events?since=$since" 2>/dev/null | BOARD_LANE="$BOARD_LANE" python3 -c '
import json, os, sys
try: evs = json.load(sys.stdin)
except ValueError: evs = []
for e in evs:
    if e["kind"] in ("order", "hold") and e.get("to") in (os.environ["BOARD_LANE"], "all"):
        print("#%(id)s %(kind)s (%(lane)s): %(text)s" % e); break' || true)
            [ -n "$hit" ] && { echo "새 지시: $hit"; echo "→ board.sh read 로 전체 확인 후 진행"; exit 0; }
            sleep 15
          done; echo "10분간 새 지시 없음 — 사람에게 다음 할 일을 묻거나 board.sh idle 을 다시 실행"; exit 0 ;;
  watch)  since=$("${CURL[@]}" "$BOARD_URL/events" | python3 -c 'import json,sys; e=json.load(sys.stdin); print(e[-1]["id"] if e else 0)')
          echo "watching from #$since"
          while sleep 10; do
            "${CURL[@]}" "$BOARD_URL/events?since=$since" 2>/dev/null | python3 -c '
import json, sys, subprocess
try: evs = json.load(sys.stdin)
except ValueError: evs = []
for e in evs:
    print("#%(id)s [%(lane)s] %(kind)s: %(text)s" % e, file=sys.stderr)
    if e["kind"] in ("human", "blocked"):
        subprocess.run(["osascript", "-e", "on run a\ndisplay notification (item 2 of a) with title (item 1 of a) sound name \"Glass\"\nend run",
                        ("🙋 " if e["kind"] == "human" else "⛔ ") + e["lane"], e["text"][:200]])
print(evs[-1]["id"] if evs else "")' > "${TMPDIR:-/tmp}/.board_since" || true
            n=$(cat "${TMPDIR:-/tmp}/.board_since"); [ -n "$n" ] && since=$n
          done ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
