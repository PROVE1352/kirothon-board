# 킥오프 절차 (팀장 맥의 Claude Code/Fable이 수행)

입력: `이름 → 레인 → 소유 디렉터리`. 예) `동욱=front-viewer(web/viewer/), 우석=front-notes(web/notes/), 규찬=pipeline, ?=api`

**대충 줘도 된다.** "front: 동욱, 민수 / back: 나, 우석"처럼 역할만 주면 Fable이 아래 규칙으로 레인을 쪼개고, 표로 한 번 보여준 뒤(팀장이 "ㅇㅇ" 하면) 바로 3~5를 진행한다. 되묻는 것은 저장소 경로가 없을 때뿐.
- 같은 역할에 N명이면 설계 문서의 화면·모듈 경계로 N개 레인으로 나눈다. 레인 이름 = `<역할>-<맡은 것>` (사람 이름 아님: 담당이 바뀌어도 레인은 남는다)
- 경계 기준: ①서로 다른 디렉터리 ②서로의 산출물을 기다리지 않고 목(mock)으로 출발 가능 ③3시간 분량이 비슷
- 팀장(나) 레인은 가장 가볍게: 팀장은 #orchestra 승인과 통합도 해야 한다

## 팀 (2026-09-20 Kirothon, 카론톤)
프론트: 동욱, 민수 / 백엔드: 규찬(팀장), 우석

잠정 레인 (claude6-harness 기준, 킥오프 때 저장소를 보고 확정)
| 레인 | 담당 | 소유 | 맡는 것 |
|---|---|---|---|
| `front-viewer` | 동욱 | `web/viewer/` | 위키 페이지 렌더, 앵커 `[[L2#s14@t=812]]` 클릭 → 슬라이드 PNG + 영상 초 점프 |
| `front-notes` | 민수 | `web/notes/` | 필기 저장 UI, 위키 성장·반려 로그 화면, 질의응답 패널 |
| `back-api` | 우석 | `api/` | 페이지·소스·필기·질의응답(⑦) API, Bedrock 연결, 정적 자산 서빙 |
| `back-pipeline` | 규찬 | `pipeline/` `hooks/` | 적재①·정렬②·컴파일③ + PreToolUse 검증 훅 + 결정적 오케스트레이터 |

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
