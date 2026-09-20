#!/usr/bin/env bash
# 팀원 노트북에서 1회 실행: ./setup.sh <레인이름> <팀토큰> [프로젝트 폴더]
#   프로젝트 폴더를 주면 .kiro/steering/board.md 와 .kiro/hooks/board-gate.json 도 넣는다
#   레인 예: viewer / pipeline / api / deck   (토큰은 팀장이 DM으로 전달 — 저장소에 올리지 말 것)
set -euo pipefail
LANE="${1:?레인 이름 필요}"; TOKEN="${2:?팀 토큰 필요}"
URL="https://board.193-123-163-215.sslip.io"
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.kiro/skills" && rm -rf "$HOME/.kiro/skills/board" && cp -R "$DIR/skill/board" "$HOME/.kiro/skills/board"
chmod +x "$HOME/.kiro/skills/board/"*.sh
# auto mode: 기본 자동 허용, 위험 명령만 물어봄. 기존 설정이 있으면 백업하고 덮어쓴다
mkdir -p "$HOME/.kiro/settings"
[ -f "$HOME/.kiro/settings/permissions.yaml" ] && cp "$HOME/.kiro/settings/permissions.yaml" "$HOME/.kiro/settings/permissions.yaml.bak-$(date +%m%d%H%M)"
cp "$DIR/kiro/settings/permissions.yaml" "$HOME/.kiro/settings/permissions.yaml"
if [ -n "${3:-}" ]; then
  mkdir -p "$3/.kiro/steering" "$3/.kiro/hooks"
  cp "$DIR/steering/board.md" "$3/.kiro/steering/board.md"
  cp "$DIR/kiro/hooks/board-gate.json" "$3/.kiro/hooks/board-gate.json"
  grep -qxF '.kiro/hooks/board-gate.json' "$3/.gitignore" 2>/dev/null || echo '.kiro/hooks/board-gate.json' >> "$3/.gitignore"  # OS별 파일이라 커밋 금지
  echo "프로젝트에 steering·hook 설치: $3/.kiro/"
fi
if grep -q '^TEAM_TOKEN=' "$HOME/.kirothon-board.env" 2>/dev/null; then
  echo "팀장용 ~/.kirothon-board.env 가 있어 덮어쓰지 않는다 (관리자 토큰 보호)"
else
  ( umask 077; printf 'BOARD_URL=%s\nBOARD_TOKEN=%s\nBOARD_LANE=%s\n' "$URL" "$TOKEN" "$LANE" > "$HOME/.kirothon-board.env" )
fi
echo "내 IP: $(curl -sS --max-time 10 "$URL/ip")  ← 403이 나오면 이 IP를 팀장에게 보낸다"
"$HOME/.kiro/skills/board/board.sh" read && echo "✅ 연결됨 (lane=$LANE)"
