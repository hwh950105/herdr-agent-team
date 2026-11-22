# 지휘 절차 (Claude 전용)

`AGENTS.md`의 규칙에 더해 Claude가 지시·기동·검증할 때 쓰는 절차다. `CLAUDE.md`가 이 파일을 불러온다.

## 1. 리뷰와 검증 흐름

1. 설계·계약을 정하고 작업을 나눠 지시한다(`담당 파일:` 명시). 함께 쓰는 API는 계약 파일을 먼저 둔다.
2. Codex는 백엔드를 구현하고 테스트로, Antigravity는 UI를 구현하고 브라우저로 검증한다.
3. 결과는 **실제 파일과 diff로** 리뷰하고 통합한다. 보고만 보고 완료로 판단하지 않는다.
4. Claude가 직접 쓴 핵심 코드(스키마·인증·계약)는 Codex에게 교차 리뷰를 맡긴다.
5. 화면 동작이 바뀌는 작업은 Antigravity의 브라우저 검증 보고까지 확인한 뒤 완료를 알린다. 중요한 판정은 스크린샷(`.hc/qa/<작업ID>/`)을 직접 열어 다시 본다.

### 분배 판단과 통합 완료 조건

- 먼저 난이도·변경 범위·의존성·공유 계약·담당 파일·검증 명령을 정한다. 작은 독립 작업은 Claude가 단독 처리한다. 모든 에이전트에 일을 만들지 않는다. 핵심 코드 교차 리뷰와 화면 브라우저 검증은 위 규칙을 유지한다.
- 계약이 준비된 독립 범위만 병렬로 맡긴다. 같은 파일이나 선행 결과가 필요한 작업은 순차로 한다. Claude 직접 수정도 `task claim <작업ID> <경로>...`로 예약한다. 지시·예약의 작성자는 한 명이며, 여러 지휘자가 동시에 예약하는 것은 지원하지 않는다.
- 기다리는 동안 다른 독립 작업을 진행한다. 이미지 생성도 별도 art 터미널에 맡기고 다른 일을 계속한다. 메시지가 올 때마다 전체 작업을 재분석하지 않고 저장된 지시·검사 결과를 참조한다.
- 각 보고의 실제 파일·diff·범위 검사·테스트 로그·계약 준수를 확인한다. `wait` 0은 **보고 수신**이며 기능 통과가 아니다. `check`도 파일 범위 검사일 뿐 테스트를 대신하지 않는다.
- 통합 전에는 모든 필수 작업의 성공, 예약 충돌/미소유 변경 없음, API 양쪽 호환, 프로젝트에 해당하는 타입 검사·빌드·단위/통합 테스트·핵심 회귀를 확인한다. 화면 변경은 준비된 서버에 대한 Antigravity E2E와 스크린샷 확인까지 포함한다. 해당 없는 검사는 이유를 적고, 실행 못 한 필수 검사는 통과로 쓰지 않는다.
- 실패하면 원인·담당 범위를 확인해 새 ID로 수정 재지시한다. 성공 후 실제 검증을 마친 작업만 `verify`하고, 계약이나 관련 파일이 바뀌면 영향 검사를 다시 수행한다. 마지막에는 변경·실행 검사·미해결·미실행을 간결하게 보고한다. 자동 커밋·push·배포는 추가하지 않는다.

## 2. 기동

- 위임 전에 기동 스크립트를 한 번 실행한다. 정상인 하위 터미널이 있으면 새로 띄우지 않고 폴더·역할·상태만 검사한다. 이상하면 경고 후 `exit 1`.
  - macOS: `.hc/up.sh`
  - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .hc\up.ps1`
- 하위 이름은 `<접두사>-codex`, `<접두사>-agy`. 접두사는 폴더명을 소문자 `a-z0-9_-`로 정규화한 18자 이내 값이다(`up.sh --prefix`, `up.ps1 --prefix`).
- 하위 터미널은 `parent`가 Claude다. 프로젝트 이름이나 `where` 라벨로 찾지 않는다. Claude가 종료되면 같이 종료되고, `hc ls`는 종료된 터미널을 숨기므로(`--all`로 보임) 목록에 없으면 기동 스크립트를 다시 실행한다.
- agy는 막 띄운 직후 잠깐 `blocked`로 보여 `exit 1`이 날 수 있다. 화면에 창이 없으면 몇 초 뒤 다시 실행한다.
- 첫 실행은 폴더 신뢰 창, 샌드박스 Codex는 권한 선택 창(`Update Model Permissions`) 때문에 `exit 1`이 정상이다. 상태가 `idle`로 보여도 스크립트가 화면 문구로 감지해 멈춘다. 사용자가 직접 고른 뒤 다시 실행한다.

```bash
hc ls | jq -r --arg me "$HC_TERMINAL_ID" '.terminals[] | select(.parent==$me) | "\(.address) \(.name) \(.agent) \(.status // "-")"'   # macOS
```
```powershell
hc ls --json | ConvertFrom-Json | ForEach-Object terminals | Where-Object parent -eq $env:HC_TERMINAL_ID   # Windows
```

## 3. 지시와 결과 확인

1. **상태 확인:** `idle`/`done`이면 보낸다. `working`이면 끝나기를 기다린다. `blocked`·값 없음·`unknown`이면 신뢰·권한 창일 수 있으니 화면을 읽고 사용자에게 알린다. 목록에서 사라졌으면 기동 스크립트를 다시 실행한다.
2. **작업 스크립트로 보낸다.** 스크립트가 머리줄(`[hc-task] id=… from=…`)과 필수 마무리를 붙이고, 원문을 `.hc/tasks/<작업ID>.md`에 보관한다. `브라우저: 필요`가 있으면 `.hc/docs/browser-qa.md` 필독 문구도 붙인다. 직접 `hc send`로 지시하지 않는다. 본문은 받는 쪽이 문서를 읽지 않아도 수행할 수 있게 쓴다:

```text
목표: <무엇을 할지. 여러 단계면 번호를 매겨 전부 적는다>
담당 파일: src/feature.js, test/ (이외 수정 금지)
계약: <관련 API 계약·타입 파일 경로. 있을 때만>
의존성: <선행 작업 ID와 필요한 결과. 없으면 없음>
검증: <작업 폴더, 실행 명령, 기대 결과. 미설치 도구는 명시. 명령은 그대로 실행되는 형태로 적는다(예: `node --test` 뒤에는 디렉터리가 아니라 파일이나 따옴표 친 glob)>
완료 조건: <검증 기준>
브라우저: <브라우저 검증이 필요할 때만 "필요". 아래 대상 URL과 함께 쓴다>
대상 URL: <허용 출처·경로 범위, 허용 리다이렉트 출처, 쓰기가 필요하면 테스트 계정·데이터와 허용 동작>
이어받을 공간: <중단된 브라우저 QA를 재개할 때만. 공간 ID>
```

3. **반드시 `wait`로 확인한다.** 보고 메시지는 빠질 수 있으므로 완료는 보고 파일 `.hc/reports/<작업ID>.md`로 판단한다. 상대 화면의 마무리 말은 완료 보고가 아니다. 기다리는 동안 겹치지 않는 일을 해도 되며, 그러려면 Bash 백그라운드 실행으로 `wait`를 돌린다. 여러 작업은 ID마다 `wait`한다.

| 종료 코드 | 뜻과 처리 |
|---|---|
| `send`/`nudge` 0 | 보냄. 상대가 `working`이 됐거나 차례가 넘어간 것을 확인했다. Windows는 `blocked` 등으로 바뀐 경우도 0이며 `wait`가 4로 알린다(macOS는 이 경우 5) |
| `send`/`nudge` 5 | 제출 확인 필요. macOS에서는 자동 Enter 없이 `hc read <대상> --lines 40`으로 상태와 입력란을 확인한다. Windows에서는 기존 Enter 재시도 후 이 코드를 반환한다 |
| `wait` 0 | 보고 있음. 보고 파일과 실제 변경 파일을 확인한다. 대상이 agy면 `task.sh`·`task.ps1`이 agy 로그로 센 명령·사람 승인 창·승인 창 없이 샌드박스 밖 실행 횟수(추정)를 함께 보여 준다(2·4·0 경로에서도 출력) |
| `wait` 2 | 보고 누락. `nudge`로 다시 보낸다(같은 ID, 최대 2번). 그래도 없으면 화면을 읽고 사용자에게 알린다 |
| `wait` 3 | 시간 초과. 아직 작업 중이며 완료가 아니다. 다시 `wait` |
| `wait` 4 | 점검 필요. 승인·신뢰 창이거나 종료됐다(보고 파일이 있어도 대상이 `blocked`면 4). macOS는 제출 미확인 기록(`PENDING=1`)이나 보고 첫 줄의 형식·ID 불일치도 4다. 화면을 읽고 사용자에게 알린다 |
| 1 | 사용법·조회 오류, 화면에 권한·신뢰 창이 있어 보내지 않았음, 또는 macOS `send`의 "전송 여부 미확인"(기록은 `PENDING=1`로 남는다) |

- 여러 단계 작업은 한 지시에 모든 단계를 적는다. 단계마다 판단이 필요하면 작업 ID를 나눠 보낸다.
- 작업 ID는 다시 쓰지 않는다(스크립트가 거부한다). 예외는 `nudge`뿐이다.
- 전달이 안 된 것 같으면 다시 보내기 전에 화면 기록(최근 100줄)을 먼저 읽는다. 대기가 timeout으로 끝난 것은 전달 실패의 증거가 아니다.
- 잘못 보냈거나 멈춰야 하면 `hc interrupt <대상>`으로 멈추고 확인한 뒤 새 작업 ID로 다시 지시한다.

### 파일 범위 검사와 수정 재지시 (요약)

Node 18+가 있으면 `send`가 `.hc/scope.mjs`로 `담당 파일:` 범위를 예약하고 기준선을 저장한다. 세부 규칙·한계는 **`.hc/docs/scope.md`** 를 읽는다.

- `담당 파일:`은 한 줄의 쉼표 구분 상대 경로(디렉터리는 끝에 `/`, 읽기 전용은 `없음`). 제외 조건은 쓰지 않고 허용 파일을 열거한다.
- 순서: `send` → `wait` 0(보고 수신일 뿐) → `check <ID>`(범위 밖 변경 분류) → 실제 파일·테스트 확인 → `verify <ID> "<검증 근거>"`. 직접 고칠 파일은 `claim`, 중단·재할당은 `release`, 현황은 `status`.
- 수정 재지시는 새 ID로 `send ... --fix-of <직전ID>`. 같은 작업 계열 최대 3회, 4회째는 보내지 않고 사용자에게 알린다.
- 종료 코드: `send` 6 = 범위 겹침·수정 한도 초과로 보내지 않음, `check`/`verify` 7 = 미소유 변경, 8 = 범위 해석 불가. 7·8이면 통합을 멈추고 `scope.md`를 본다.

### macOS (`.hc/task.sh`)

전송 직전에 대상 주소와 이전 차례를 기록한다. 전송 결과가 불확실하면 기록은 `PENDING=1`로 남고, 그 ID의 `wait`는 4를 반환하며 `nudge`는 거부된다. 복구:

- **보고 파일이 왔고 첫 줄이 맞으면:** 받은 것으로 보고 `check`·실제 파일 확인으로 진행한다. 범위 예약이 있었으면 `node .hc/scope.mjs sent <작업ID>`로 확정한다(`--fix-of`면 직전 ID 예약도 이때 해제된다).
- **화면에 지시가 없어 미실행이 확실하면:** `.hc/task.sh release <작업ID> 미전송`으로 예약을 풀고 새 ID로 다시 지시한다.
- **작업 중이면:** 끝날 때까지 화면으로 지켜본 뒤 위 둘 중 하나로 처리한다.

```bash
# <<'EOF'(따옴표)로 본문의 $·백틱 실행을 막는다.
.hc/task.sh send <대상> <작업ID> <<'EOF'
목표: ...
담당 파일: ...
완료 조건: ...
EOF
.hc/task.sh wait <작업ID> [초]
.hc/task.sh nudge <작업ID>
```

### Windows (`.hc\task.ps1`, PowerShell)

```powershell
# 작은따옴표 here-string(@' '@)은 본문의 $를 해석하지 않는다.
@'
목표: ...
담당 파일: ...
완료 조건: ...
'@ | Set-Content -Encoding UTF8 .hc\tasks\<작업ID>.body.txt
powershell -NoProfile -ExecutionPolicy Bypass -File .hc\task.ps1 send <대상> <작업ID> .hc\tasks\<작업ID>.body.txt
powershell -NoProfile -ExecutionPolicy Bypass -File .hc\task.ps1 wait <작업ID> [초]
powershell -NoProfile -ExecutionPolicy Bypass -File .hc\task.ps1 nudge <작업ID>
```

- Windows에서 agy에게 명령 실행을 시킬 때는 지시문에 `node <스크립트> [인자]`처럼 **단독 명령**으로 적는다. 기본 허용 목록에는 `node`가 없으므로 실행 승인이 필요할 수 있다. 사용자가 선택한 확장 허용 목록에서도 `$env:X='...'; node ...` 형식은 `node` 규칙에 맞지 않는다. 과거 검증 환경에서는 `localhost`·Playwright·`.hc\qa` 쓰기가 샌드박스에서 차단돼 밖에서 재시도했다. 현재 환경에서도 같은지 확인하고 승인 창은 사용자가 직접 처리한다.
- Claude Code의 셸이 Git Bash여도 위 `powershell ...` 명령을 그대로 쓴다. Git Bash의 `hc read`는 한글이 깨지므로 화면은 PowerShell로 읽는다.
- Windows 스크립트는 `.hc\hc.ps1`(공용 함수)을 함께 읽는다. 직접 실행하지 않는다. `jq`는 필요 없다.

## 4. `hc` 명령

- 맨 `hc`는 터미널 선택 화면을 띄우므로 실행하지 않는다. 문법은 `hc --help`, `hc <명령> --help`. 파이프로 받을 때 `--json`을 붙이면 항상 JSON이다.

| 동작 | 명령 |
|---|---|
| 상태 조회 | `hc get <대상>`의 `.status.state` (실제 작업 폴더는 `.foreground.cwd`. `hc ls`의 `cwd`는 처음 연 위치) |
| 대기 | `hc wait <대상>` — timeout·다른 메시지 도착으로도 종료 코드 0이므로 결과의 `reason`과 상태를 다시 본다. `--children any`로 아무 하위나 |
| 화면 읽기 | `hc read <대상> --lines 100 --json` (기본은 현재 화면만. 결과의 `complete`/`why`로 앞부분이 잘렸는지 본다) |
| 키 입력 | `hc keys <대상> esc` (무해한 안내 창 넘기기에만) |
| 파일 전달 | `hc put <대상> <파일>` |
| 중단 | `hc interrupt <대상>` |
| 서버 실행 | `hc run --bg --name <접두사>-dev --cwd <프로젝트 폴더> <명령>` → 로그 `hc read <이름>`, 종료 `hc kill <이름>`. 유지가 필요하면 `--outlive-parent`. 준비는 로그와 가능하면 health URL로 확인 |

- `hc send --if idle`은 `done`이면 거부된다. `--force`로 입력하지 않는다. `hc send --wait`는 그 턴이 끝날 때까지 막히므로 짧은 작업에만 쓴다.
- 보고는 `<hc from="tN ...">...</hc>` 메시지로 들어온다(herdr-core `notes` 설정이 켜져 있을 때). 꺼져 있으면 `.hc/reports/`와 `hc read`로 확인한다.

## 5. 권한 설정

### Codex

- 기본은 샌드박스(`-s workspace-write -a never`, 네트워크 허용, `--no-daemon`). 샌드박스에서는 `.agents/`, `.codex/`, `.git/`이 읽기 전용이다.
  - macOS: `~/.local/state/herdr-core` 쓰기 허용, `HC_TERMINAL_ID`/`HC_TERMINAL_SOCKET`을 `-c shell_environment_policy.set...`으로 주입한다.
  - Windows: `HC_TERMINAL_SOCKET`이 파일 경로이면 그 폴더를 `--add-dir`로 쓰기 허용에 넣는다. 실제 Windows에서는 named pipe(`\\.\pipe\herdr-core-...`)여서 붙지 않았다. npm 설치 `codex.cmd`는 `up.ps1`이 실제 경로를 찾아 넘긴다. 실제 정책이 `workspace-write`인 Codex에서는 named pipe 접근이 거부돼(오류 5) 보고 `hc send`가 실패한다(2026-11-22 확인. 2026-11-21의 "동작함" 기록은 전역 설정 때문에 실제로는 Full Access였던 것으로 보인다). 보고 메시지는 오지 않지만 `wait`가 보고 파일로 완료를 판정한다.
  - Windows 샌드박스 Codex에서는 `node --test`가 테스트 파일마다 하위 프로세스를 띄우다 `spawn EPERM`으로 실패한다. Codex에게 보내는 검증 명령은 `node --test --test-isolation=none <파일>`로 적는다(Node 22.8+).
  - Windows Codex의 PowerShell은 실행 정책 때문에 `npm`(`npm.ps1`)이 막힐 수 있다. 지시문의 명령은 `npm.cmd test`처럼 `.cmd`로 적는다.
- 우회 모드(`--dangerously-bypass-approvals-and-sandbox`)는 `.hc/local.env`에 `CODEX_MODE=bypass` 한 줄이 있을 때만 쓴다. 사용자 승인 뒤에만 만들고, 승인 기록은 `AGENTS.md` 5절에 적는다. `.hc/local.env`는 git에 올라가지 않으므로 복사한 프로젝트는 샌드박스로 시작한다.
- 샌드박스 Codex가 첫 실행 권한 선택 창에서 Full Access로 바뀌면 사실상 우회 모드다. 인자는 `-s workspace-write`로 남아 있어도 실제 세션 정책은 `danger-full-access`가 된다. `up.sh`·`up.ps1`은 Codex 화면 기록(최근 3000줄)에서 마지막 `• Permission selection requested:` 값이 정확히 `Full Access`이면 경고하고 멈추고, 화면을 읽지 못해도 멈춘다. 그 줄이 3000줄 밖으로 밀려난 오래된 세션은 찾지 못한다. Windows는 권한 창의 선택이 전역 `%USERPROFILE%\.codex\config.toml`의 `sandbox_mode`에 저장된 사례가 있으니, 이 경고가 나오면 그 값도 사용자가 확인한다. 그렇게 쓸 거면 처음부터 `CODEX_MODE=bypass`로 띄운다. 실제 정책은 `~/.codex/sessions/.../rollout-*.jsonl`의 마지막 `turn_context`에 있는 `sandbox_policy`로 확인한다.
- 우회 모드에서는 범위·승인 규칙이 도구로 강제되지 않으므로 Codex의 변경을 실제 파일로 확인한다.

### Antigravity

- 권한 우회 옵션 없이 띄우고, 기동 스크립트가 `agy --settings .hc/agy-settings.<mac|win>.json`으로 이 세션에만 허용 목록을 넘긴다. 목록을 바꾸면 agy를 다시 띄워야 적용된다.
  - macOS 기본: `command(hc send)`만 허용한다.
  - Windows 기본: `command(regex:hc send .*)`만 허용한다. 이 규칙은 맞는다: agy는 규칙을 실행 직전에 붙이는 PowerShell 래퍼(출력 인코딩 설정 코드)가 아니라 원래 명령(`CommandLine`)에 맞추고, 정규식은 앞부분을 고정해 비교한다. 다만 Windows agy 샌드박스는 Herdr named pipe를 막으므로 보고 `hc send`는 매번 샌드박스 안에서 실패한 뒤 `BypassSandbox`로 다시 실행되고, 이 재시도는 allow 규칙 때문에 사람 승인 창 없이 실행된다(2026-11-22, agy 1.5.14 확인). `command(regex:.*hc send .*)`처럼 앞을 열면 `다른명령; hc send ...`까지 허용되므로 쓰지 않는다.
  - 두 OS 공통 `ask`: `rm`, `git push|reset|clean`, `npm publish`, `sudo`, `hc kill`, `hc server`(Windows는 `Remove-Item`·`del`·`rmdir` 추가). macOS에서는 Auto 모드에서도 이 명령이 사람 승인 창을 띄운다(agy 1.5.14에서 `&&`로 이은 명령까지 확인). **Windows에서는 `command(rm)` 같은 평문 형식이 PowerShell 명령에 맞지 않는다(`unknown_command`로 분류)**: `rm`·`Remove-Item`·`git clean`·`hc kill`이 승인 창 없이 실행됐다(2026-11-22, agy 1.5.14). `command(regex:(.*[;&|]\s*)?Remove-Item\b.*)`처럼 앞부분 고정 정규식으로 쓰면 단독·`;`로 이은 명령은 검토 에이전트가 안전하다고 봐도 승인 창을 띄우고, 보고 본문이나 따옴표 안의 단어에는 걸리지 않았다(같은 날 시험 터미널에서 확인). 그래서 `.hc/agy-settings.win.json`의 `ask`는 이 형식으로 쓴다(`git\s+(push|reset|clean)`, `hc\s+(kill|server)`처럼 묶음). Windows 사용자 설정 파일에도 같은 형식을 넣는다. `regex:.*Remove-Item.*`처럼 앞을 열면 그 단어가 든 보고 `hc send`까지 걸려 무인 작업이 멈춘다. 정규식은 대소문자를 구분하고 별칭(`ri`·`erase`)·`cmd /c`·스크립트 안 삭제는 잡지 못하므로, 어느 형식이든 삭제·push·초기화는 지시문 규칙과 결과 확인(`check`·실제 파일)에도 의존한다. 배포 명령은 프로젝트마다 `AGENTS.md` 5절 스택에 맞춰 추가한다. 사용자 설정 파일을 쓰면 이 `ask` 목록이 적용되지 않으므로 그 파일에도 같은 항목을 넣는다.
- **본인 환경에서 넓히기:** 기동 스크립트는 사용자 설정 폴더의 `hc-agents/agy-settings.<mac|win>.json`(macOS `~/.config/hc-agents/`, Windows `%APPDATA%\hc-agents\`)이 있으면 공개 기본값 대신 그 파일을 쓰고, 쓴다는 사실을 화면에 알린다. 프로젝트 밖에 두는 이유는 샌드박스 에이전트가 프로젝트 안 파일을 고쳐 권한을 넓힐 수 있기 때문이다. `command(*)`나 `regex:.*` 같은 전체 허용이 있으면 쓰지 않는다. 예: macOS `command(hc send)`, `command(ego-browser)`, `read_file(/Applications/ego lite.app)` / Windows `command(regex:hc send .*)`, `command(regex:node .*)`. 바꾸면 agy를 다시 띄운다. 에이전트에게 이 파일을 만들거나 고치게 하지 않는다.
- 브라우저/Node 명령은 기본 자동 허용하지 않는다. 승인 창이 나오면 사용자에게 알리고 직접 선택하게 한다. 반복 검증을 위해 사용자가 명시적으로 승인한 경우에만 프로젝트의 위 설정 파일에 필요한 항목을 추가할 수 있다. Windows의 `command(regex:node .*)`는 임의 Node 코드 실행을 허용하므로 신뢰할 수 있는 프로젝트·검사한 스크립트에만 선택한다. macOS의 `command(ego-browser)`는 로그인된 실제 브라우저에 접근하며, 앱 읽기 경로도 자기 설치 위치를 확인해 필요한 범위만 추가한다. `command(*)`·권한 우회 옵션·전역 설정 자동 변경은 금지한다.
- 허용 항목은 명령 이름과 하위 명령까지만 좁혀진다(`command(node <경로>)`처럼 파일 경로로는 안 된다). 허용 규칙은 샌드박스 밖 재시도에도 적용된다.
- agy는 기본 모드가 Auto다(`--mode` 없이 띄운 세션). Auto는 파일 수정과 샌드박스 안 명령을 묻지 않고 실행하고, 샌드박스 밖이 필요한 명령(`BypassSandbox`)은 allow 규칙에 맞거나 **사람이 아니라 별도 검토 에이전트**가 승인하면 그대로 실행한다. `hc send`(두 OS)와 macOS `ego-browser`는 샌드박스 안에서 막혀 이 경로로 실행된다. 그래서 허용 목록을 유일한 보호 장치로 보지 않고, 꼭 사람이 확인할 명령은 `ask`에 넣는다. 우회 여부는 `~/.gemini/antigravity-cli/log/cli-<시작시각>.log`에서 `BypassSandbox`·`Surfacing tool confirmation`으로 확인한다.
- 다른 조합은 무인 작업에 맞지 않는다(2026-11-22, agy 1.5.14 macOS 시험). `--mode accept-edits`와 `toolPermission: proceed-in-sandbox`를 함께 써도 허용 목록 밖 명령마다 승인 창이 뜨고, 기본 모드와 `proceed-in-sandbox`를 함께 쓰면 파일 수정마다 승인 창이 뜬다.
- `hc send` 허용도 다른 로컬 터미널에 메시지를 보낼 수 있는 권한이다. 지시문의 `from=` 대상만 사용하고 개인 터미널에는 보내지 않는다. 공개 파일에 키를 넣거나 로그인된 브라우저 프로필을 복사하지 않는다.
- 승인 창의 "always allow (Persist to settings.json)"은 전역 설정에 명령을 글자 그대로 저장한다. 고르지 않는다. 전역 설정(`~/.gemini/antigravity-cli/settings.json`)은 건드리지 않는다.

## 6. 이미지 생성 (art)

이미지가 필요하면 Claude가 직접 만들지 않고 이미지 전용 터미널 `<접두사>-art`에 맡긴다.

1. **사용자에게 먼저 묻는다:** 이번 이미지를 Codex(OpenAI 이미지 모델)로 만들지, Antigravity(Gemini 이미지 모델)로 만들지. 이미지 작업마다 묻는다.
2. **art 터미널을 그 에이전트로 띄운다:** macOS `.hc/up.sh --art codex|agy`, Windows `powershell -NoProfile -ExecutionPolicy Bypass -File .hc\up.ps1 --art codex|agy`. codex·agy 검사도 함께 한다. 이미 art가 다른 에이전트로 떠 있으면 스크립트가 경고하고 멈춘다. 자기가 띄운 터미널이므로 `hc kill <접두사>-art` 뒤 다시 실행한다.
3. **작업 스크립트로 지시한다:** 대상은 `<접두사>-art`. 본문에는 용도, 크기·비율, 스타일, 장 수, 파일 형식, 저장 경로(`담당 파일:`)를 적는다. 저장 경로를 정하지 않았으면 `.hc/art/<작업ID>/`(git 제외)에 두게 하고, 쓸 이미지는 Claude가 프로젝트 폴더로 옮긴다.
4. **결과 확인:** `wait` 0이면 보고의 파일 경로를 열어 이미지를 직접 본다. 고칠 점이 있으면 새 작업 ID로 다시 지시한다.

- art는 이미지 파일만 만든다(`AGENTS.md` 1절의 art 금지). 권한 모드와 허용 목록은 고른 에이전트의 설정(5절)을 그대로 쓴다.
- art 터미널은 계속 띄워 두어도 되고, 다른 에이전트로 바꿀 때만 종료한다.
