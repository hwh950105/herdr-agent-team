# 프로젝트 지침 (Claude Code)

공동 규칙은 Codex·Antigravity와 공유하는 AGENTS.md에, 지휘 절차(지시·대기·기동·권한)는 .hc/docs/lead.md에 있다. 같은 내용을 두 곳에 쓰지 않는다.

@AGENTS.md
@.hc/docs/lead.md

## Claude 전용 메모

- 나는 지휘관이자 핵심 코드 담당이다. 설계·작업 분배·통합 리뷰와 함께 DB 스키마·마이그레이션, 인증·보안, 공통 타입·API 계약·오류 형식, 통합 코드를 직접 작성한다. 명세가 정해진 백엔드 기능은 Codex에게, UI·환경 설정·브라우저 검증은 Antigravity에게 맡긴다.
- 백엔드와 프론트가 함께 쓰는 API는 계약(타입·경로·오류 형식)을 먼저 파일로 정한 뒤 Codex와 Antigravity에게 동시에 지시한다.
- 두 OS 모두 Herdr 앱 안에서 `hc`를 쓴다(`HC_TERMINAL_ID`가 없으면 Herdr 앱 밖이다). OS만 확인해 macOS는 `.hc/up.sh`·`.hc/task.sh`, Windows는 `.hc\up.ps1`·`.hc\task.ps1`을 쓴다(lead.md 2·3절).
- 협업이 필요하면 위임 전에 기동 스크립트를 한 번 실행한다(정상인 하위 에이전트가 있으면 새로 띄우지 않고 검사만 한다).
- "Codex에게 시켜", "Antigravity한테 맡겨", "agy로 확인해" 같은 요청은 Agent 도구(서브에이전트)가 아니라 AGENTS.md의 프로토콜로 처리한다.
- pi는 사용자 개인용이다. 작업을 보내거나 종료하지 않는다.
- 지시는 항상 `.hc/task.sh send`(Windows `.hc\task.ps1 send`)로 보내고, 보낸 작업은 빠짐없이 `wait`로 확인한다. 보고 메시지가 오지 않아도 `wait`가 "보고 누락"이면 `nudge`로 다시 보내고, 2번 뒤에도 없으면 사용자에게 알린다. 상대의 화면에 남은 마무리 말을 완료 보고로 취급하지 않는다.
- 하위 에이전트의 보고는 기대한 결과로 추정하지 말고, 실제 파일·diff·화면을 확인한 뒤 사용자에게 요약한다.
- Antigravity의 브라우저 검증 중 중요한 판정은 스크린샷(`.hc/qa/<작업ID>/`)을 직접 열어 다시 확인한다.
