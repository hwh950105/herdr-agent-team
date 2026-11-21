# Windows 셋팅 진행 기록과 문제점

- 날짜: 2026-11-21
- 환경: Windows 11 Pro 10.0.26200, Windows PowerShell 5.1.26100, Herdr 앱 + herdr-core `hc 0.1.21`
- 도구: node v26.13.1, codex-cli 0.171.0, agy 1.5.14, Playwright 1.65.1
- 기준 문서: `README.ko.md` "에이전트용 셋팅 절차 > Windows"

## 단계별 결과

| # | 단계 | 결과 | 비고 |
|---|---|---|---|
| 1 | Herdr 앱 안인지 | 완료 | `HC_TERMINAL_ID=t2` |
| 2 | herdr-core(`hc`) | 완료 | `hc 0.1.21` (`C:\Users\<사용자>\AppData\Local\Programs\herdr-core\hc.exe`) |
| 3 | 옛 `herdr` TUI 없음 | 완료 | 없음 |
| 4 | Node.js | 완료 | v26.13.1 |
| 5 | Codex CLI | 완료 | 0.171.0 (npm 전역, `codex.cmd`) |
| 6 | Antigravity CLI | 완료 | 1.5.14 (`C:\Users\<사용자>\AppData\Local\agy\bin\agy.exe`) |
| 7 | Playwright | 조치 후 완료 | 처음엔 없음 → `npm i -D playwright`, `npx playwright install chromium` 실행 |
| 8 | 로그인 | 완료 | `agy models` 목록 나옴. Codex는 신뢰 뒤 바로 입력 가능(로그인 상태) |
| 9 | Codex 권한 모드 | 건너뜀 | `.hc\local.env` 없음 → 기본 샌드박스 |
| 10 | 하위 터미널 기동 | 사용자 조치 후 완료 | 1차 `exit=1`(신뢰 창, P3) → 사용자 신뢰 → 2차 `exit=0`. Codex 권한 선택 창(P5)은 사용자가 Full Access 선택(P9) |
| 11 | 통신 확인 | **부분 완료** | agy·Codex 모두 보고 파일 OK. 단 Codex는 지시가 제출되지 않아 사용자가 Enter(P6), agy는 보고 `hc send`마다 승인 창(P7) |
| 12 | 브라우저 확인 | 완료 (승인 창 1회) | Playwright로 `https://example.com` 제목 `Example Domain` 확인, 스크린샷 `.hc\qa\setup-agy-browser\example.png` 직접 확인. 보고 전송은 다시 승인 창(P7) |

## 확인된 사항 (README "검증 범위"의 미확인 항목)

### Windows의 `HC_TERMINAL_SOCKET`은 named pipe다
- 실제 값: `\\.\pipe\herdr-core-<사용자>-default.sock`
- `up.ps1`은 이 경우 `--add-dir`를 붙이지 않도록 이미 분기돼 있다(정상 동작).
- 남은 확인: Codex 샌드박스(`workspace-write`) 안에서 named pipe로 `hc send`가 되는지. 11단계에서 확인한다.

## 문제점

### P1. `.gitignore`에 `node_modules/`가 없다 (중요도: 중)
- 현상: 7단계 조치(`npm i -D playwright`)를 하면 `node_modules/`, `package.json`, `package-lock.json`이 생기고 `git status`에 그대로 잡힌다.
- 영향: 실수로 `node_modules/`가 커밋될 수 있다. 템플릿을 새 프로젝트에 복사할 때 원래 프로젝트에 없던 `package.json`이 섞인다.
- 제안: `.gitignore`에 `node_modules/`를 추가한다. 템플릿 저장소 자체에는 Playwright를 프로젝트 의존성으로 두지 말고, `.hc/qa/` 아래에서만 쓰거나 전역 설치(`npm i -g playwright`)를 안내하는 방안을 검토한다.

#### P1 해결 (적용)
- `.gitignore`에 `node_modules/`를 추가했다.
- `package.json`·`package-lock.json`은 `.gitignore`에 넣지 않았다. 이 `.gitignore`는 새 프로젝트에 그대로 복사되므로, 넣으면 그 프로젝트의 진짜 `package.json`까지 무시된다. 템플릿 저장소에서는 커밋하지 않고 로컬에만 둔다.

### P2. 7단계 확인 명령이 비대화형에서 오해를 부른다 (중요도: 하)
- 현상: Playwright가 없을 때 `npx playwright --version`은 설치 여부를 묻거나, 비대화형 셸에서는 `npx canceled due to missing packages and no YES option`으로 실패한다. 설치하겠냐고 물을 때 에이전트가 그대로 진행하면 확인 단계에서 패키지가 내려받아진다.
- 제안: 확인 명령을 `npx --no-install playwright --version`으로 바꾼다.

### P3. 첫 기동 때 신뢰 창 때문에 `up.ps1`이 항상 `exit 1`로 끝난다 (중요도: 하, 예상된 동작)
- 현상: Codex는 `Trust this folder?`, agy는 `Do you trust the contents of this project?` 창을 띄우고 멈춘다. `up.ps1`은 60초를 기다린 뒤 경고하고 `exit 1`.
  - codex: `status=-`, `app=` (비어 있음), `fg=node.exe`
  - agy: `status=blocked`, `app=antigravity`
- 영향: README "문제 해결"에 적힌 대로 사용자가 직접 고른 뒤 다시 실행하면 된다. 다만 첫 실행이면 반드시 겪는 일이라 10단계 표에 "첫 실행 시 두 터미널에서 신뢰 선택 필요"를 미리 적어 두면 덜 헷갈린다.
- 참고: Codex 창에 "Trusting will apply to the repository root"라고 나온다. 신뢰가 저장소 루트 단위로 저장된다.

### P4. Windows에서 Codex 역할 판정이 앱 감지에만 기대고 있다 (중요도: 중, 확인 중)
- 현상: npm 전역 설치 Codex는 `codex.cmd` → `node.exe codex.js`로 실행된다. 그래서 `foreground.name`이 `node.exe`다.
- `up.ps1`의 `Test-Terminal`은 `status.app`이 비어 있으면 `foreground.name`(확장자 제외)이 `codex`인지로 역할을 판정한다. Windows에서는 `node`라서 이 대체 판정이 절대 통과하지 못한다.
- 영향: herdr-core가 `status.app=codex`를 늦게 감지하거나 못 하면, 신뢰 선택 뒤에도 "재사용·준비 조건 불일치"로 `exit 1`이 될 수 있다.
- 제안: `foreground.argv`에 `@openai\codex` 또는 `codex.js`가 들어 있으면 codex로 인정한다.
- 상태: 신뢰 선택 뒤 `up.ps1` 재실행 결과로 확인한다(아래 갱신).

### P5. Codex 첫 실행의 권한 선택 창이 떠 있어도 `status=idle`로 보고된다 (중요도: 상)
- 현상: 신뢰를 고른 뒤 Codex(t4)가 `Update Model Permissions` 창(1. Ask for approval / 2. Approve for me / 3. Full Access / 4. Read Only)을 띄운다. 그런데 `hc get t4`는 `status.app=codex`, `status.state=idle`이고, `up.ps1`도 `t4 ... codex idle`, `exit=0`으로 끝난다.
- 영향: `up.ps1`과 `task.ps1 send`의 상태 검사를 그대로 통과한다. 이때 지시를 보내면 본문이 선택 창에 키 입력으로 들어가 엉뚱한 권한이 골라지거나 지시가 사라질 수 있다. 특히 3(Full Access)이 골라지면 `-s workspace-write -a never`로 띄운 샌드박스 의도가 깨진다.
- 제안:
  - `up.ps1`이 `idle` 판정 뒤에 `hc read <t> --lines 40`으로 화면을 한 번 더 보고 `Update Model Permissions`, `Trust this folder`, `enter select` 같은 문구가 있으면 "점검 필요"로 처리한다(`task.ps1 send` 직전에도 같은 검사).
  - README 10단계에 "Codex 첫 실행 시 권한 선택 창이 뜬다. 사용자가 직접 고른다(CLI 인자의 샌드박스 설정을 유지하려면 `esc`)"를 적는다.

### P6. Codex에 `hc send`로 보낸 지시가 입력만 되고 제출(Enter)되지 않는다 (중요도: 상)
- 현상: `task.ps1 send t4 setup-codex-ping ...`은 `exit 0`(turn=1)으로 끝났다. 하지만 Codex 입력란에 본문만 들어가고 제출되지 않았다. **사용자가 직접 Enter를 눌러야** 실행됐다. agy(t5)는 같은 방식으로 바로 실행됐다.
- 추정 원인: 여러 줄 본문이 Codex TUI에서 "붙여넣기"로 처리되고, 이어서 보내는 Enter가 붙여넣기 안의 줄바꿈으로 흡수되거나 너무 빨리 들어가 무시되는 것으로 보인다. 확인되지 않음.
- 영향: 무인으로 Codex에 일을 맡길 수 없다. `task.ps1 wait`는 Codex가 시작하지 않으면 1800초 뒤 "시간 초과(3)"만 보고하므로 원인을 알기 어렵다.
- 제안:
  - `hc send` 도움말: "Paste text into a terminal and press Enter". 즉 hc는 붙여넣기 뒤 Enter를 보내지만 Codex가 그 Enter를 받지 못한 것이다. hc/Codex 쪽 문제로 보고할 만하다.
  - 스크립트 대응: `task.ps1 send` 뒤 3~5초 안에 대상 상태가 `working`이 되거나 turn이 늘지 않으면 `hc keys <대상> enter`로 제출 키를 한 번 더 보낸다(입력란에 본문이 남아 있는지 `hc read`로 먼저 확인).
  - `wait`에서 "보낸 뒤 N초가 지나도 turn이 늘지 않음"을 별도 종료 코드(예: 5 "미제출")로 구분한다.

#### P6 해결 (적용·확인 완료)
- `.hc/task.ps1`에 `Confirm-Submitted`를 추가했다. `send`·`nudge`는 보내기 직전의 대상 `turn`을 기억하고, 보낸 뒤 6초 안에 `working`이 되거나 `turn`이 늘었는지 본다. 아니면 `hc keys <대상> enter`로 Enter를 다시 누른다(최대 2번). 그래도 시작하지 않으면 `미제출`을 출력하고 종료 코드 **5**로 끝난다.
- 확인(verify-codex-1): `알림: t4 이(가) 지시를 시작하지 않아 Enter를 다시 누릅니다 (1/2)` → Codex가 바로 시작했고 사람의 조작 없이 끝까지 진행됐다. Codex는 이번에도 첫 Enter를 놓쳤으므로 문제는 재현됐고 우회가 동작한다.
- 한계: macOS `task.sh`에는 아직 적용하지 않았다. 근본 원인(hc의 붙여넣기 뒤 Enter를 Codex가 놓침)은 hc/Codex 쪽 문제로 남는다.

### P7. agy의 보고용 `hc send`가 Windows 샌드박스에 막히고, 허용 목록이 있어도 승인 창이 뜬다 (중요도: 상)
- 현상(t5 화면): "The Windows sandbox denies access to the named pipe. Retrying the operation with sandbox bypass enabled." → 샌드박스 밖 재시도에서 승인 창이 떴다. 사유: "The command sends a message via `hc send` to `t2`, a pre-existing local terminal ... not created or started by the coding agent".
- 즉 `.hc/agy-settings.win.json`의 `command(hc send)` 허용은 (1) 샌드박스의 named pipe 차단을 풀지 못하고, (2) 샌드박스 우회 실행과 자체 안전 판정의 승인 창도 막지 못한다. README의 "승인 창이 뜨지 않아야 한다"와 다르다.
- 영향: 매 보고마다 사람이 승인해야 한다. 승인 전까지 agy가 `blocked`인데, 보고 파일은 이미 있어서 `task.ps1 wait`는 `0 보고 있음`으로 끝난다(아래 P8).
- 제안: agy 설정에서 herdr-core named pipe(`\\.\pipe\herdr-core-*`) 접근을 샌드박스 허용에 넣을 방법이 있는지 확인한다(agy 설정 스키마 확인 필요). 없으면 Windows에서는 "보고 메시지는 승인이 필요할 수 있고, 완료 판단은 보고 파일로 한다"를 README에 명시한다.
- 참고: Codex는 사용자가 Full Access를 골라 샌드박스 밖이라 `hc send`가 바로 성공했다. 샌드박스(`workspace-write`) 상태의 Codex에서 named pipe가 되는지는 **여전히 미확인**이다.

#### P7 해결: 허용 규칙을 정규식 형식으로 바꾼다 (적용·확인 완료)

**원인.** Antigravity 공식 문서(<https://antigravity.google/docs/permissions.md>)에 따르면 Windows 셸(PowerShell, cmd)에서 깔끔하게 나눌 수 없는 명령은 접두사 매칭이 안 되고 **정확히 일치해야** 한다. `hc send t2 '[hc-report] ... 요약: ...'`처럼 따옴표·한글·대괄호가 섞인 명령이 여기에 해당해서 `command(hc send)` 규칙이 무시됐다. 문서는 이 경우 `command(regex:git .*)` 형식을 쓰라고 한다. 정규식 규칙은 공백으로 나눈 토큰마다 앞뒤가 고정된(anchored) 정규식으로 비교한다.

또한 문서(<https://antigravity.google/docs/sandbox.md>)에 따르면 `command(...)` 허용 규칙은 **샌드박스 안팎 모두**에 적용된다. 그래서 샌드박스가 named pipe를 막아 agy가 샌드박스 밖에서 재시도해도 규칙에 맞으면 승인 없이 실행된다. named pipe 자체를 샌드박스에 허용하는 규칙은 문서에 없다(`write_file`/`read_file`/`read_url`만 있음).

**설정 방법.**

1. `.hc/agy-settings.win.json`을 다음처럼 바꾼다.

   ```json
   {
     "permissions": {
       "allow": [
         "command(regex:hc send .*)",
         "command(regex:node .*)"
       ]
     }
   }
   ```

   - 변경 전: `command(hc send)`, `command(node)`
   - `node`도 경로(`node .hc\qa\...\check.mjs`)가 붙으면 같은 문제가 생길 수 있어 같이 바꿨다. 허용 범위는 원래 의도(`node` + 아무 인자)와 같다.
2. 이 파일은 `agy --settings <파일>`로 **시작할 때만** 읽힌다. 이미 떠 있는 agy는 다시 띄워야 적용된다.

   ```powershell
   hc kill <접두사>-agy          # 예: hc kill herdr-agent-team-agy (Claude가 띄운 하위 터미널만)
   powershell -NoProfile -ExecutionPolicy Bypass -File .hc\up.ps1
   ```

3. 짧은 작업(예: `$env:HC_TERMINAL_ID` 출력)을 `task.ps1 send`로 보내고, agy 화면에 `Run this command?` 창 없이 보고가 오는지 확인한다.

**확인 결과(setup-agy-allow2).** agy를 t6으로 다시 띄운 뒤 보고가 사람의 조작 없이 도착했다. agy 화면 기록: 1차는 샌드박스 안에서 `os error 5`(named pipe 접근 거부)로 실패했고, 2차는 `BypassSandbox: true`로 바로 성공했다(종료 코드 0). 승인 창은 남아 있지 않았다.

**주의.**
- 매 보고마다 "샌드박스 안 시도 → 실패 → 밖에서 재시도"를 하므로 몇 초가 더 걸린다. 일반(비기업) 계정은 `unsandboxed(...)` 규칙을 쓸 수 없어서 첫 시도를 건너뛸 방법이 없다.
- `hc send .*`는 agy가 **어느 터미널에든** 메시지를 보낼 수 있게 허용한다. 범위를 좁히려면 `command(regex:hc send t[0-9a-z]+ .*)`처럼 쓸 수 있지만, 따옴표 안 문자열이 토큰으로 어떻게 나뉘는지는 확인하지 않았다.
- 승인 창에서 "3. always allow (Persist to settings.json)"을 고르면 **전역** `~/.gemini/antigravity-cli/settings.json`에 그 명령이 **글자 그대로** 저장된다. 작업 ID와 요약이 매번 달라서 다음 보고에는 효과가 없고 전역 설정만 지저분해진다. 이번 셋팅 중 고른 두 항목(`setup-agy-ping`, `setup-agy-browser` 보고)이 이미 전역 파일에 들어가 있다. `AGENTS.md` 규칙상 전역 설정은 에이전트가 건드리지 않으므로, 필요하면 사용자가 직접 지운다.

### P8. `task.ps1 wait`가 대상이 승인 창에서 `blocked`여도 보고 파일만 있으면 0으로 끝난다 (중요도: 중)
- 현상: setup-agy-ping에서 agy가 보고 파일을 쓴 뒤 `hc send` 승인 창에 멈췄는데 `wait`가 `보고 있음`, `exit 0`.
- 원인: 보고 파일이 있으면 `Get-State`가 `working`이 아닌지만 본다. `blocked`도 통과한다.
- 영향: 다음 지시를 보내려 하면 `send`가 `상태=blocked`로 거부해 그제야 알게 된다.
- 제안: 보고 파일이 있고 상태가 `blocked`이면 "보고 있음(대상은 승인 대기 중)"을 따로 출력하거나 4를 돌려준다.

#### P8 해결 (적용, 실제 재현은 못 함)
- `wait`에서 보고 파일을 찾은 뒤 대상 상태를 다시 보고, `idle`/`done`이 아니면 `점검 필요: 보고 파일은 있지만 <대상> 상태=<상태>`를 출력하고 종료 코드 **4**로 끝나게 했다. 상태가 `working`이면 원래대로 끝날 때까지 기다린다.
- P7을 해결해서 승인 창이 더 이상 뜨지 않아 `blocked` 경로를 실제로 재현하지는 못했다. 정상 경로(보고 있음 + `idle`/`done` → 0)는 verify-codex-1, verify-agy-1에서 확인했다.
- `AGENTS.md` 2-2절 `wait` 결과 표의 4번 설명과 `send`의 종료 코드 5 설명을 고쳤다.

### P9. Codex 권한 선택 창에서 Full Access가 선택되어 샌드박스가 꺼졌다 (중요도: 중, 확인 필요)
- 현상: t4 화면에 `Permission selection requested: Full Access`. `up.ps1`은 `-s workspace-write -a never`로 띄웠지만 TUI 선택이 이를 덮어쓴 것으로 보인다.
- 영향: `AGENTS.md` 5절의 "권한 우회 모드는 사용자 승인 + `.hc/local.env` + 6절 기록" 절차를 거치지 않고 사실상 우회 모드가 됐다. `.hc/local.env`는 여전히 없어서 스크립트와 실제 상태가 다르다.
- 제안: P5의 제안대로 첫 실행 권한 창을 스크립트가 감지하게 한다. Full Access를 계속 쓸 거면 `.hc/local.env`에 `CODEX_MODE=bypass`를 두고 6절에 승인 기록을 남긴다.

#### P4·P5·P9 해결 (적용, macOS에서 확인)
- P5: `up.ps1`·`up.sh`는 `idle`/`done` 판정 뒤, `task.ps1`·`task.sh`의 `send`·`nudge`는 보내기 직전에 현재 화면(`hc read`)을 보고 `Update Model Permissions`, `Trust this folder`, `Do you trust the contents`, `Requesting permission for`, `Run this command?`가 있으면 멈춘다. 화면 문구 감지는 macOS에서 가짜 창 문구로 확인했다.
- P9: 2026-11-21 사용자가 Codex Full Access 사용을 결정했다. 그 Windows 환경의 `.hc\local.env`에 `CODEX_MODE=bypass`를 두고 `up.ps1`로 다시 띄운다(우회 모드에서는 권한 선택 창이 없다). 템플릿 기본값은 계속 샌드박스다.
- P4: `up.ps1`은 `status.app`이 비어 있으면 `foreground.argv`에 `@openai\codex` 또는 `codex.js`가 있는지로도 Codex를 판정한다.
- P6·P8은 macOS `task.sh`에도 같은 방식으로 넣었다.

### P10. README 12단계의 확인 기준이 현재 example.com 화면과 다르다 (중요도: 하)
- 현상: 지금 `https://example.com`의 `<title>`은 `Example Domain`이지만 본문에는 그 헤딩이 없다(아이콘, 다국어 안내 문구, `Learn more` 링크만 있음). Claude가 스크린샷을 직접 열어 확인했다.
- 영향: "화면에서 Example Domain이 보이는지" 시각 판정을 시키면 실패로 판단할 수 있다. 이번에는 agy가 title 일치와 본문 차이를 구분해 보고했다.
- 제안: 12단계 기준을 "`page.title()`이 `Example Domain`이고 스크린샷이 저장됨"으로 명확히 한다.

### 기타 (저장소 외부 또는 사소)
- Codex 화면에 `Hook failed — unsupported plugin entry type: ...\.codex\plugins\cache\sisyphuslabs\omo\4.19.1\...codex-comment-checker`가 명령마다 반복된다. 사용자 전역 Codex 플러그인(omo) 문제라 이 저장소와는 무관하지만 화면 기록(`hc read`)을 많이 차지한다.
- Git Bash에서 `hc read`를 하면 한글·기호가 깨진다(`??`, `쨌`). PowerShell에서는 정상이다.
- Codex 화면에서 보고 경로가 `C:\Users\<사용자>\herdr-agent-team.hc\reports\...`처럼 `\`가 하나 빠져 보인다. 마크다운 렌더링 때문이며 실제 파일은 올바른 경로에 생겼다.

## 진행 기록 (갱신)

- 10단계 1차 실행: 위 P3으로 `exit=1`. 사용자가 t4·t5에서 신뢰를 고름.
- 10단계 2차 실행: `exit=0`, `t4 herdr-agent-team-codex codex idle`, `t5 herdr-agent-team-agy antigravity idle`.
  - **P4 결과:** herdr-core가 `status.app=codex`를 감지해서 이번 환경에서는 문제가 나타나지 않았다. 다만 앱 감지가 실패하면 쓸 대체 판정은 여전히 Windows에서 통과할 수 없으므로 수정은 권한다.
  - agy(t5)는 "Introducing Gemini 4 Neon" 안내(`esc to dismiss`)만 있고 입력란이 살아 있다. 진행에 지장 없음.
  - Codex(t4)는 P5의 권한 선택 창에서 대기. 사용자 선택을 기다리는 중.
- 11단계: setup-agy-ping(agy) `wait=0`, 보고 메시지는 사용자 승인 뒤 도착. setup-codex-ping(Codex) `wait=0`, 사용자가 Enter를 쳐서 시작됨, 보고 `hc send` 성공(Full Access 상태).
- 12단계: setup-agy-browser `wait=0`, Playwright 정상. 보고 메시지는 사용자 승인 뒤 도착(P7 재현).
- 셋팅 중 생긴 파일(git 미추적): `node_modules/`, `package.json`, `package-lock.json`(P1), `docs/windows-setup-issues.md`(이 문서). `.hc/tasks`, `.hc/reports`, `.hc/qa`는 git 제외 대상.

## 우선 처리 권장 순서

1. ~~**P6**~~ Codex 지시 미제출 → **해결**(`task.ps1` Enter 재시도, 종료 코드 5)
2. ~~**P7**~~ agy 보고 승인 창 → **해결**(허용 규칙을 `command(regex:hc send .*)`로 변경, 위 "P7 해결" 참고). ~~**P8**~~ `wait`의 blocked 구분 → **해결**(종료 코드 4)
3. ~~**P5/P9**~~ Codex 첫 실행 권한 창 감지 → **해결**, Full Access → `CODEX_MODE=bypass`로 사용(사용자 결정)
4. ~~**P1**~~ `.gitignore`에 `node_modules/` 추가 → **해결**
5. ~~P2·P3·P10~~ 문서 수정 → **해결**, ~~P4~~ 대체 판정 보강 → **해결**

## 기능 확인 (P6·P7·P8 수정 후)

| 대상 | 작업 | 확인한 기능 | 결과 |
|---|---|---|---|
| Codex (t4) | verify-codex-1: `.hc/qa/verify-codex/slugify.mjs` + `node:test` 테스트 | 지시 자동 제출(P6), 백엔드 구현·테스트, 보고 파일 + `hc send` 보고 | 완료. Enter 1번 다시 눌러 시작. Claude가 `node --test`를 다시 실행해 **8개 통과 / 0개 실패** 확인 |
| agy (t6) | verify-agy-1: `.hc/qa/verify-agy/index.html` 카운터 화면 + Playwright 검증 | 화면 구현, Playwright 브라우저 검증·스크린샷, `node` 허용 규칙, 승인 창 없는 보고(P7) | 완료. Claude가 `check.mjs`를 다시 실행해 `0 → 3 → 0` 확인, `count3.png`를 직접 열어 화면(Counter, 3, +1/초기화 버튼) 확인. 승인 창 없음 |
| `task.ps1 wait` | 두 작업 | 보고 파일 기반 완료 판단, P8 상태 재확인 | 둘 다 `exit 0` |

남은 확인 사항: 샌드박스(`workspace-write`) Codex에서 named pipe로 `hc send`가 되는지(현재 Full Access라 미확인), P8의 `blocked` 경로 실제 재현, macOS `task.sh`에 같은 수정 반영.
