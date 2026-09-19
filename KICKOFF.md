# 킥오프 절차 (팀장 맥의 Claude Code/Fable이 수행)

입력: `이름 → 레인 → 소유 디렉터리`. 예) `동욱=front-viewer(web/viewer/), 우석=front-notes(web/notes/), 규찬=pipeline, ?=api`

원칙
- **레인 = 한 Kiro가 소유하는 디렉터리.** 같은 역할(프론트)이라도 사람마다 레인을 따로 준다. 같은 레인을 둘이 쓰면 hold·보고가 섞이고 파일이 충돌한다.
- IP는 사람 식별이 아니다(현장 와이파이는 전원 같은 NAT IP). 식별은 각자 `setup.sh`에 넣은 레인 이름.
- Fable은 계획·계약·리뷰만. 코드는 Kiro. Kiro는 commit/push 금지(사람이 직접).

순서
1. 프로젝트 저장소에서 설계 정본(claude6-harness v1.1, PLAN.md) 읽기
2. `CONTRACT.md`: 레인별 소유 디렉터리 + 레인 간 인터페이스(앵커 규약, API 스키마, 산출물 경로). 변경은 `board.sh human` 경유
3. `lanes/<레인>.md`: 목표 / 30분 단위 태스크 / 완료 조건 / 건드리면 안 되는 곳 / 기다리는 다른 레인 산출물과 그동안 쓸 목(mock)
4. 커밋·푸시
5. 레인마다 `board.sh order <레인> "git pull 후 lanes/<레인>.md 읽고 1번부터. 계약은 CONTRACT.md"`
6. 현장 IP 1회 등록: 팀원 `board.sh ip` → 팀장 `board.sh allow <ip> "현장"`
7. `~/discord-ai-bridge/.env`의 `BOARD_REPO=<저장소 경로>` 설정 후 봇 재시작 → #orchestra의 Fable 의견이 실제 코드를 읽는다
8. 팀원: `git pull` → Kiro에 "상황판 읽고 시작해"

진행 중: #orchestra에서 human에 ✅/❌, 필요 시 `!next <레인>`. 1h·2h 지점에 Fable에게 "통합 점검" (레인 간 계약 어긋남 찾기). 마지막 30분은 `!hold all` 후 통합·발표 준비.
