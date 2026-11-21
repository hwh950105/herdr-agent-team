# 자동화 개선 검증 기록

2026-11-21, Windows 11·PowerShell 5.1·Node 26·Herdr `hc 0.1.21`에서 확인했다. Claude가 사용량 한도로 중단한 `automation-improvements` 브랜치를 사용자 지시로 Codex `t4`가 이어받았다. 기존 Todo 프로젝트 `C:\Users\hwh\herdr-todo-test`와 기존 에이전트 `t7`(Codex), `t8`(Antigravity), 서버 `t10`을 재사용했다. Claude의 응답이나 새 기동에 의존하지 않았다.

기준 구현은 `f5c9f34`이며, 이번에는 문서와 핵심 방어 로직을 보완했다. 배포·push·전역 권한 변경·기존 터미널 종료는 하지 않았다. 원래 프로젝트의 미추적 `package.json`, `package-lock.json`도 수정하지 않았다.

## 판정 기준

- 실제 에이전트 작업, 실제 파일시스템 검사, 모의 의존성, 의도적 실패 주입, 미실행을 구분한다.
- `wait` 0은 보고 수신이며 테스트 성공이 아니다. failed 보고도 수신 자체는 0이다.
- 실제 파일·diff·명령 재실행·스크린샷을 확인한 뒤 별도 verified 기록을 남겼다. 보고 첫 줄은 기존 `done|failed|blocked`를 유지한다.

## 요구사항 시나리오

| 번호 | 결과·방식 | 근거 |
|---|---|---|
| 1 작은 작업 단독 | 절차 구현, 원래 Claude 단독 시나리오는 미실행 | Claude 한도로 이번 지휘는 사용자 지정 Codex가 수행. 일반 단독/위임 기준은 `lead.md`에 명시 |
| 2 백엔드 Codex 배정·검증 | 실제 실행 | `automation-backend-failure`→`automation-backend-fix`, `automation-final-review`. 실제 health GET과 테스트 추가. 최종 `npm.cmd test` 43/43 |
| 3 UI 배정·브라우저 | 실제 실행 + 쓰기 응답 모의 | `automation-ui`, `automation-ui-integration`. 입력 오류 연결·main 접근성 이름 추가. 실제 페이지/GET, 브라우저 route로 POST만 모의. 데스크톱·모바일 통과 |
| 4 독립 병렬·통합 | 실제 실행 | t7의 백엔드 테스트 보강·코어 리뷰와 t8의 UI 보강·E2E가 동시 working인 목록을 보존. 지휘 측에서도 최종 백엔드 43/43와 E2E를 병렬 재실행해 통과 |
| 5 실패 후 수정 재지시 | 실제 에이전트 + 통제된 기대값 오류 주입 | 첫 health 테스트를 의도적으로 `{ok:false}`와 비교해 pass0/fail1, failed 보고. 새 ID와 `--fix-of`로 `{ok:true}`로 수정, pass1/fail0 및 전체 테스트 통과. 제품 자체의 장애를 발견한 사례는 아님 |
| 6 수정 3회 후 중단 | 모의 CLI 테스트 | 원래 작업 이후 수정 1~3회 허용, 4회째 코드6. 옛 부모에서 분기해 회차를 초기화하는 우회도 거부. 실제 에이전트에 4번 실패시키지는 않음 |
| 7 소유 충돌·통합 중단 | 실제 예약/파일 검사 + 통제된 파일 주입 | 실제 활성 작업의 파일 중복 claim 코드6. `automation-boundary`에서 미소유 marker를 주입해 check7·verify7, verified 파일 미생성 확인. 인수 사유/별도 예약 후 재검사0. 다른 에이전트가 실제로 규칙을 위반한 사례는 아님 |
| 8 이미지 대기 중 독립 작업 | 미실행 | 이미지별 Codex/Antigravity 사용자 선택을 요청했으나 이번 실행에서 선택이 확정되지 않았다. 이미지 생성·art 기동 없음 |
| 9 보고 누락 재촉 | 모의 hc + 실제 task.ps1 실행 | 누락 wait2, nudge 2회 성공·3회 거부, timeout3, blocked4, failed 보고 수신0, 보고 존재+blocked4를 확인. 실제 에이전트의 보고를 일부러 누락시키지는 않음 |
| 10 실제 검증 후 보고 | 실제 실행 | 지휘 측 테스트/E2E 재실행, 실제 diff, 두 화면 직접 확인, scope check/verify 기록. macOS·이미지 미실행도 구분 |

## 핵심 코드 교차 리뷰와 수정

Codex `t7`의 `automation-core-review`, `automation-final-review`를 실제 파일·독립 재현 근거로 검토했다. 이번 보완 내용은 다음과 같다.

- 해석 불가 범위는 check/verify 8로 중단하며 verified를 만들지 않는다.
- 수정은 마지막 작업에서만 이어간다. 최종 보고 전 분기, 형제 분기로 회차 한도 우회, 다른 범위로 ID 재사용을 막는다. 미전송 재개는 원래 기준선을 보존한다.
- 부모 예약은 자식 전송 기록이 생긴 뒤 내부 sent 단계에서 해제한다. 실패 시 부모와 pending 자식을 남기며, 전달 여부를 확인하기 전 자동 중복 전송하지 않는다.
- 병렬 작업을 순서대로 verify해도 정상 변경을 오탐하지 않는다. 완료된 작업의 면제는 검증/해제 시점의 정확한 파일 해시에 한정해 이후 변경을 숨기지 않는다.
- verified 이후 디렉터리 파일 추가·삭제도 변경 표시한다. 보고의 작업 ID도 일치해야 한다.
- 경로 별칭을 정규화하고 링크·하드 링크·Unicode/대소문자 이름 충돌은 안전하게 중단한다. 원본 파일명 키를 보존해 정규화 충돌에 따른 해시 덮어쓰기를 막는다.
- 읽기 실패·손상된 기록을 무시하지 않는다. 큰 파일도 고정 크기 버퍼로 전체 내용 해시를 계산한다. verify 판정과 기록은 같은 스냅샷을 사용한다.

초기 추가 회귀 검사에서는 7건 실패를 실제 관측한 뒤 수정했다. Unicode 이름 충돌도 별도 실패 테스트를 먼저 확인했다. 최종 핵심 테스트는 **27개 통과, 실패0, 건너뜀0**이다. 읽기 오류는 mock 주입이며 실제 ACL 변경은 하지 않았다. 링크·하드 링크·Unicode 이름 충돌은 Windows의 독립 임시 파일로 확인했다.

최종 `automation-review-closure`에서 Codex가 수정 차이와 27개 테스트를 다시 확인했다. 단일 지휘자·순차 예약 전제 안에서 새로 확인된 차단 결함은 없었다. 검토된 SHA-256은 `scope.mjs`=`69cf71b6f9b85c49210f83e49348dfbc5a132738d4b30ad291cc7ff1348ba1ba`, `scope.test.mjs`=`95033bf0cc1d57c68a1848ec3058164f17b7dc5ca17e5daaf72c44660f920b60`이다. 동시 예약 경쟁은 제거됐다고 판정하지 않았다.

## 실행 명령과 증거

| 실행 위치·명령 | 결과 |
|---|---|
| 템플릿: `node --test .hc/scope.test.mjs` | 27/27, 실패0 |
| 템플릿: PowerShell Parser의 `ParseFile`로 `.hc/task.ps1` 확인 | 문법 오류0 |
| 템플릿: Git Bash `bash -n .hc/task.sh` | 종료0, 문법 검사만 |
| 템플릿: `node .hc/qa/automation-final/protocol-regression.mjs` | 실제 task.ps1 + 모의 hc 의존성, 예상 종료 코드 11개와 art 주소/브라우저 머리말 단언 통과 |
| 템플릿: `node .hc/qa/automation-final/wrapper-send-failure.mjs` | 모의 전송 실패 후 부모 예약 보존·자식 pending 확인 |
| 템플릿: `node .hc/qa/automation-final/live-boundary.mjs` | 실제 Todo 작업 기록/파일 검사, 중복6·미소유7·verify 거부7·사유 있는 인수 후0 |
| Todo: `npm.cmd test` | 지휘 측 최종 재실행 43/43, 실패0 |
| Todo: `node e2e/automation.e2e.mjs` | 지휘 측 최종 재실행 종료0. 1280×800, 390×844, main/입력 접근성·오류·목록·남은 개수·가로 넘침 단언 통과 |
| 템플릿: `git diff --check` | 공백 오류 없음 |

로컬 증거는 git 제외 경로에 보존했다.

- 템플릿 `.hc/qa/automation-final/`: 프로토콜/전송 실패/경계 검사 스크립트와 fixture, `live-boundary-results.json`, `parallel-terminals.json`, `backend-final.txt`, `browser-final.txt`.
- Todo `.hc/tasks/`: 각 작업의 원문·scope·check·verified/released 기록. 실패 작업은 후속 수정으로 인수되었다.
- Todo `.hc/reports/automation-*.md`: 실제 에이전트별 검증·교차 리뷰 보고.
- Todo `.hc/qa/automation-review/`, `.hc/qa/automation-final-review/`: 교차 리뷰의 버전별 고정 스냅샷·해시·독립 재현 결과.
- Todo `.hc/qa/automation-ui/`: 오류/생성 화면 데스크톱·모바일 PNG 4장. 지휘 측도 직접 열어 한국어 줄바꿈·겹침·오류 표시를 확인했다.
- Todo `automation-validation/`: 미소유 변경 검사에 사용한 marker 2개를 삭제하지 않고 인수 기록과 함께 보존했다.

QA 재현 파일들은 이번 작업의 로컬 증거다. 위 경로의 이전 실패 하네스도 삭제하지 않았다. 초기 프로토콜 하네스의 mock 인자 바인딩 오류는 수정 후 재실행해 통과했으며 제품 결함으로 세지 않는다.

## 지원 범위와 남은 한계

- **예약 호출은 지휘자 한 명이 순차로 실행한다.** 실제 작업 실행만 병렬화한다. 독립 리뷰가 두 Node 프로세스의 동시 start로 같은 파일을 이중 예약하는 경쟁을 재현했다. 이 경쟁은 제거되지 않았다. 잠금·별도 서버 없는 요구 범위에서 문서상 지원 전제로 제한했으며, 다중 지휘자·동시 예약 호출을 지원한다고 주장하지 않는다.
- 공유 폴더에서는 변경자를 식별할 수 없다. 다른 활성 작업 범위에 들어간 침범, 검사 사이 원복, 검사 직후 외부 변경을 모두 잡는 도구가 아니다. 제외 폴더·실행 비트·권한 변경도 내용 스냅샷으로 보장하지 않는다.
- 실행 중 SQLite 서버의 정상 GET도 `data/e2e.db-shm`을 바꿀 수 있었다. 최초 check가 7로 중단한 뒤 서버 부산물임을 확인하고 `automation-runtime`으로 `data/`를 명시적으로 예약·인수했다. 검사에서 이 경로를 몰래 제외하지 않았다. 기존 서버는 계속 실행 중이며 종료하지 않았다.
- 이번 브라우저 검증에서 실제 서버에는 GET만 전송했다. POST는 UI 반응 확인용 모의 응답이다. 실제 CRUD·영속성은 기존 41개 API 테스트의 메모리/임시 SQLite 및 이전 Todo E2E 기록과 구분한다.
- Antigravity의 Windows 샌드박스에서는 QA 쓰기/localhost 접근이 실패했고 기존 허용 규칙으로 샌드박스 밖 재시도 후 통과했다. 전역 설정이나 허용 목록을 넓히지 않았다.
- 새 task.sh의 **macOS 실제 실행은 미실행**이다. 현재 Windows Git Bash에서 문법만 검사했고 jq도 없어 전송/대기 런타임을 macOS 검증으로 표시하지 않았다. 이미지 시나리오 역시 미실행이다.
