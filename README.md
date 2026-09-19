# kirothon-board

노트북마다 Kiro 1대 + 팀장 맥의 Fable(오케스트라). 코드는 git, "지금 어디까지"는 이 상황판.
서버: stockllm `kirothon-board.service` (127.0.0.1:8377) ← Caddy `https://board.193-123-163-215.sslip.io`

## Kiro 세팅 (팀원, 1회 · 2분)
```bash
git clone https://github.com/PROVE1352/kirothon-board && cd kirothon-board
./setup.sh <레인> <팀토큰> <프로젝트 폴더>
```
이 한 줄이 하는 일:

| 설치 위치 | 무엇 | 역할 |
|---|---|---|
| `~/.kiro/skills/board/` | SKILL.md · board.sh · gate_hook.sh | 상황판 읽기·보고·정지 대기 (Kiro는 `~/.kiro/skills/`의 SKILL.md를 자동 인식) |
| `~/.kirothon-board.env` | URL · 팀 토큰 · 내 레인 이름 | 권한 600, 저장소에 올리지 않음 |
| `~/.kiro/settings/permissions.yaml` | auto mode | 기본 전부 자동 허용, `sudo`·`rm -rf`·`git reset --hard`·`git clean -f`는 물어봄, **`git commit`·`git push`·PR 생성은 차단**(사람이 직접. Kiro는 커밋에 적을 내용만 제안) (기존 파일은 `.bak-날짜`로 백업) |
| `<프로젝트>/.kiro/steering/board.md` | 항상 켜진 규칙 | 태스크 전 read · 끝나면 done · 사람 판단은 human→wait |
| `<프로젝트>/.kiro/hooks/board-gate.json` | AgentStop 훅 | 턴이 끝날 때 새 커밋이 있으면 상황판에 자동 보고 — 사람이 직접 Kiro를 모는 레인(프론트)도 피드가 끊기지 않음 |
| 〃 | PreToolUse 훅 | 내 레인이 정지 상태면 **도구 호출 자체를 차단**(exit 2). 커밋·푸시 명령도 여기서 한 번 더 차단. board.sh 호출과 서버 불통 시에는 통과 |

레인 이름은 `KICKOFF.md` 명단의 자기 이름(`front-dongwook` `front-minsu` `back-kyuchan` `back-wooseok`). 403 `ip … not allowed`가 나오면 출력된 IP를 팀장에게 보낸다. 와이파이를 바꾸면 IP도 바뀐다.

확인(1분): Kiro를 프로젝트 폴더에서 열고 "상황판 읽고 내 레인 상태 보고해"라고 시킨다 → 디스코드 `#orchestra`에 글이 뜨면 끝.
훅 확인: 팀장이 `!hold <내 레인> 테스트` → Kiro에 아무 파일이나 고치라고 시킴 → 🛑 메시지와 함께 막히면 정상 → `!release <내 레인>`.

- Kiro IDE와 Kiro CLI v3(`kiro-cli --v3`) 모두 `.kiro/hooks/*.json`(version v1) 형식을 읽는다. CLI v2의 에이전트 내장 훅 형식은 지원하지 않는다 — v2면 steering 규칙만으로 동작(협조적 정지).
- 훅 파일 형식은 kiro.dev/docs/hooks 기준으로 작성했고 훅 스크립트는 단독 테스트를 통과했다. **실제 Kiro 세션 안에서의 차단은 위 "훅 확인"으로 각자 1회 검증할 것.**

## 팀장
```bash
B=~/.kiro/skills/board/board.sh
$B allow 1.2.3.4 "동욱 집"     # IP 등록 (CIDR 가능) / $B deny … / $B allowed
$B watch                        # 터미널 하나에 띄워 둠 → human·blocked 오면 macOS 알림
$B read                         # 전체 판
$B order viewer "A로 가"        # 지시 (그 레인의 human 정지도 풀림)
$B hold all "계약 재정리 5분"   # 전원 정지 → $B release all
```
토큰: `~/.kirothon-board.env` 의 `BOARD_TOKEN`=관리자(팀장만), `TEAM_TOKEN`=팀원 배포용. 관리자 토큰은 IP 제한을 받지 않는다(어디서든 IP를 등록해야 하므로).

## 보안 모델
팀 토큰 + IP allowlist 둘 다 통과해야 읽기·쓰기. order/hold/release/allow 는 관리자 토큰만. 팀원에게 서버 SSH 계정은 주지 않는다.
현장 와이파이는 전원이 같은 NAT IP로 보이므로 그 IP 하나만 등록하면 된다(= 같은 와이파이의 타인은 토큰으로만 막힌다).

## 디스코드 (팀장 맥의 discord-ai-bridge + board_gate.py)
`#orchestra` = 진행 피드 + 승인. `human` 글에 ✅ → 그 레인 재개 / ❌ → 정지 유지 / 답글 → 그 내용이 지시로 전달되고 재개. `!board` `!hold` `!release` `!order`.
- `human`/`blocked`/`ask`에는 Fable(저장소 읽기 전용)이 의견을 답글로 달고, `human`에는 grok이 그 의견의 반론을 단다. 결정은 사람.
- `!next <lane> [메모]` — Fable이 그 레인의 다음 지시 초안을 쓰고, ✅를 누르면 order로 전송. `done`마다 자동 지시는 하지 않는다(각 Kiro는 자기 tasks 목록대로 간다).
- 질문·의견·반론·결정은 Inkling "진행 로그" 페이지에 쌓인다.

## 한계
PreToolUse 훅이 있으면 정지는 다음 도구 호출에서 바로 걸린다(게이트 결과 20초 캐시). 훅이 없는 환경(CLI v2)에서는 협조적 정지라 태스크 경계까지 몇 분 걸릴 수 있다. 서버에 못 닿으면 훅은 통과시킨다(fail-open).

## 끝나면
`ssh stockllm 'sudo systemctl disable --now kirothon-board'` + Caddyfile의 board 블록 삭제(백업 `Caddyfile.bak-board-0919`).
