# Herdr Agent Team: Claude · Codex · Antigravity 멀티 에이전트 셋팅

[English](README.md) | **한국어**

[Herdr](https://herdr.dev) 안에서 **Claude Code가 지휘관 겸 핵심 코드 담당**이 되어 **Codex**(백엔드 구현)와 **Antigravity**(`agy`, UI 구현·브라우저 검증)를 옆 터미널로 띄우고, 정해진 형식의 메시지로 작업을 주고받는 공동 작업 폴더 템플릿입니다. 프로젝트 이름에 의존하지 않으므로 새 프로젝트에 파일을 그대로 복사해 씁니다. **macOS와 Windows**를 모두 지원합니다.

```
사용자 ──▶ Claude (지휘 + 스키마·인증·공통 타입·통합)
             ├─ [hc-task] ─▶ Codex       (<접두사>-codex)  백엔드 API·로직·연동·테스트
             └─ [hc-task] ─▶ Antigravity (<접두사>-agy)    화면·폼·API 연결 + 브라우저 E2E
                 ◀─ [hc-report] ─┘
pi: 사용자 개인용 (개발 분담 제외)
```

## 역할

| 담당 | 직접 작성 | 책임 |
|---|---|---|
| **Claude** | DB 스키마·마이그레이션, 인증·보안, 공통 타입·API 계약·오류 형식, 통합 코드 | 설계, 작업 분배, 통합 리뷰 |
| **Codex** | 명세가 정해진 기능 API·서비스 로직, 외부 연동, 백엔드 테스트, 대규모 리팩터링 | API 동작·데이터 정합성 검증 |
| **Antigravity** | 화면·컴포넌트·폼, 상태 바인딩, API 연결, 로딩·오류 처리, 환경 설정·빌드 스크립트 | 브라우저에서 사용자 흐름 검증 |
| **art** | 이미지 생성. 필요할 때만 `<접두사>-art` 터미널을 띄우고, 이미지마다 Codex·Antigravity 중 무엇으로 만들지 사용자에게 묻는다 | 지정한 경로에 이미지 파일만 만든다 |
| **pi** | 개인 작업 | 개발 분담에서 제외 |

공통 규칙(역할·소유 경계, 보고, 안전)은 [`AGENTS.md`](AGENTS.md), Claude의 지휘 절차는 [`.hc/docs/lead.md`](.hc/docs/lead.md), 브라우저 검증 규칙은 [`.hc/docs/browser-qa.md`](.hc/docs/browser-qa.md)에 있습니다.

## macOS와 Windows의 차이

| | macOS | Windows |
|---|---|---|
| Herdr | **Herdr 앱** + herdr-core(`hc`) | **Herdr 앱** + herdr-core(`hc`) |
| 에이전트 통신 명령 | `hc send` / `hc wait` / `hc read` | 같음 |
| 자기 주소 | `$HC_TERMINAL_ID` (예: `t2c`) | `$env:HC_TERMINAL_ID` |
| 스크립트 | `.hc/up.sh`, `.hc/task.sh` (bash, `jq` 필요) | `.hc\up.ps1`, `.hc\task.ps1`, `.hc\hc.ps1` (PowerShell) |
| 레이아웃 | bercail (선택) | 기본 레이아웃 |
| 브라우저 검증 | ego lite (`ego-browser`) | Playwright |

두 OS 모두 같은 Herdr 앱과 `hc` 명령을 씁니다. 메시지 형식(`[hc-task]`/`[hc-report]`)과 역할·규칙도 같고, 다른 것은 스크립트 언어·레이아웃·브라우저 도구뿐입니다.

## 파일 구성

| 파일 | 내용 |
|---|---|
| `AGENTS.md` | 세 에이전트가 매 세션 읽는 공통 규칙(약 75줄). 역할·소유 경계, 보고 원칙, 안전 규칙, 프로젝트별 설정 칸 |
| `CLAUDE.md` | Claude Code 전용 메모. `@AGENTS.md`와 `@.hc/docs/lead.md`를 불러온다 |
| `.hc/docs/lead.md` | Claude 전용 지휘 절차: 기동, 지시·대기·종료 코드, `hc` 명령, OS별 명령, Codex·agy 권한 설정 |
| `.hc/docs/browser-qa.md` | 브라우저 검증 규칙. `브라우저: 필요` 지시에는 작업 스크립트가 필독 문구를 자동으로 붙인다 |
| `.hc/up.sh` | macOS: Codex·Antigravity 하위 터미널을 띄우거나 검사 |
| `.hc/up.ps1` | Windows: `up.sh`와 같은 일을 PowerShell로 한다 |
| `.hc/hc.ps1` | Windows: `up.ps1`·`task.ps1`이 함께 쓰는 공용 함수(직접 실행하지 않음) |
| `.hc/agy-settings.mac.json`, `.hc/agy-settings.win.json` | Antigravity 세션 전용 허용 목록. 보고·브라우저 명령의 승인 창을 없앤다 |
| `.hc/task.sh`, `.hc/task.ps1` | 작업 지시 보내기·기다리기·보고 확인. 보고 메시지가 빠져도 보고 파일로 완료를 판단하고, 누락이면 이어서 하라고 다시 보낸다 |
| `.hc/tasks/` | 보낸 지시 원문과 대기 기록(git 제외) |
| `.hc/local.env` | 이 작업 환경 전용 설정(git 제외). `CODEX_MODE=bypass`가 있으면 Codex를 권한 우회 모드로 띄운다 |
| `.hc/reports/` | 에이전트 보고서(git 제외) |
| `.hc/art/` | art가 만든 이미지의 기본 저장 위치(git 제외) |
| `.hc/qa/` | 브라우저 검증 스크린샷·증거(git 제외) |
| `docs/windows-setup-issues.md` | Windows 실환경 셋팅 기록과 문제점·해결 |

## 빠른 시작: 에이전트에게 셋팅 맡기기

Herdr 앱을 설치하고, 이 폴더에서 **Herdr 앱 안의 터미널**로 Claude Code(`claude`)를 켠 뒤 아래 문장을 붙여 넣습니다. Herdr와 Claude Code 설치·로그인은 사람이 직접 합니다.

```text
README.ko.md의 "에이전트용 셋팅 절차"에서 지금 OS에 맞는 표를 위에서부터 차례대로 실행해서 이 폴더의 멀티 에이전트 환경을 셋팅해 줘.
각 단계는 확인 명령부터 돌리고, 이미 되어 있으면 건너뛰어. "사용자 확인" 표시가 있는 단계는 실행 전에 나에게 물어봐.
끝나면 단계별 결과(완료/건너뜀/사용자 조치 필요)를 표로 정리해 줘.
```

### 에이전트용 셋팅 절차

> 이 절은 셋팅을 맡은 에이전트(Claude Code)가 읽고 실행하는 절차다. 각 단계는 **확인 → (없으면) 조치 → 재확인** 순서로 진행한다. 한 단계가 실패하면 다음으로 넘어가지 말고 원인과 출력을 사용자에게 보고한다.
>
> 에이전트가 대신 하면 안 되는 것: 대화형 로그인(`claude`/`codex`/`agy` 첫 로그인), 신뢰·권한 대화창의 키 입력, `sudo`·관리자 권한 명령, 권한 우회 모드 승인. 이런 단계에서는 멈추고 필요한 조치를 정확한 명령과 함께 알려 준다. 사용자가 직접 실행할 명령은 프롬프트에 `! <명령>`으로 입력하라고 안내한다.

#### macOS

| # | 단계 | 확인 명령 (통과 조건) | 조치 (확인 실패 시) |
|---|---|---|---|
| 1 | Herdr.app 안인지 | `echo "$HC_TERMINAL_ID"` (비어 있지 않음) | **중단.** Herdr.app 안의 터미널에서 `claude`를 다시 켜 달라고 한다 |
| 2 | herdr-core(`hc`) | `hc --version` | **사용자 확인** 후 `curl -fsSL https://releases.herdr.dev/core/install.sh \| sh`. 맨 `hc`는 실행하지 않는다 |
| 3 | 옛 `herdr` CLI가 없는지 | `command -v herdr` (출력 없음이 정상) | **사용자 확인.** 옛 CLI는 앱과 다른 서버를 쓰므로 macOS에서는 지우는 것을 권한다 |
| 4 | jq | `command -v jq` | `brew install jq` |
| 5 | Codex CLI | `command -v codex` | `npm i -g @openai/codex@latest` (`EACCES`면 사용자가 `sudo chown -R "$(id -u):$(id -g)" ~/.npm` 실행 후 재시도) |
| 6 | Antigravity CLI | `agy --version` | **사용자 조치.** Antigravity 앱을 설치하고 앱 안내에 따라 `agy`를 PATH에 등록. 없으면 `export PATH="$HOME/.local/bin:$PATH"` 후 재확인 |
| 7 | ego lite | `ego-browser --version` | **사용자 조치.** ego lite 앱을 설치하고 첫 실행 안내를 마친다 |
| 8 | 로그인 | `agy models` (모델 목록). Codex는 사용자에게 묻는다 | **사용자 조치.** 별도 터미널에서 `codex`, `agy`를 한 번씩 실행해 로그인 |
| 9 | Codex 권한 모드 | `cat .hc/local.env 2>/dev/null` | 기본은 샌드박스라 조치 없음. **사용자가 원할 때만** 승인 후 `CODEX_MODE=bypass`를 적고 `AGENTS.md` 5절에 승인 기록을 남긴다 |
| 10 | 하위 터미널 기동 | `.hc/up.sh; echo "exit=$?"` (`exit=0`, 둘 다 `idle`) | 아래 "문제 해결". **첫 실행은** Codex·agy가 폴더 신뢰 창을 띄워 `exit=1`로 끝나는 것이 정상이다. 사용자가 두 터미널에서 직접 고른 뒤 다시 실행한다 |
| 11 | 통신 확인 | Antigravity에게 `[hc-task]`로 `echo "$HC_TERMINAL_ID"` 같은 짧은 작업을 보내고 `[hc-report]`가 오는지 본다 | `up.sh`가 `.hc/agy-settings.mac.json` 허용 목록을 넘기므로 승인 창이 뜨지 않아야 한다. 뜨면 화면을 사용자에게 보고하고, 필요한 명령을 허용 목록에 추가할지 묻는다 |
| 12 | 브라우저 확인 | Antigravity에게 `브라우저: 필요`, `대상 URL: https://example.com`(읽기 전용)으로 페이지 제목(`page.title()`이 `Example Domain`)을 확인하고 스크린샷을 `.hc/qa/<작업ID>/`에 저장하게 한다 | 실패하면 화면을 사용자에게 보고 |
| 13 | (선택) bercail 테마 | `test -f ~/.config/herdr-app/layouts/bercail.json` | **사용자 확인.** 원하면 [레이아웃 절](#레이아웃-macos-bercail-windows-기본) 안내 |

#### Windows

PowerShell 기준입니다. Claude Code는 **Herdr 앱 안의 터미널**에서 실행해야 합니다. 레이아웃은 기본 레이아웃을 씁니다.

| # | 단계 | 확인 명령 (통과 조건) | 조치 (확인 실패 시) |
|---|---|---|---|
| 1 | Herdr 앱 안인지 | `$env:HC_TERMINAL_ID` (비어 있지 않음) | **중단.** Herdr 앱 안의 터미널에서 `claude`를 다시 켜 달라고 한다 |
| 2 | herdr-core(`hc`) | `hc --version` | **사용자 확인** 후 Herdr 앱 설치(`powershell -c "irm https://releases.herdr.dev/app/install.ps1 \| iex"`, herdr-core 포함). `hc`만 없으면 `powershell -c "irm https://releases.herdr.dev/core/install.ps1 \| iex"`. 맨 `hc`는 실행하지 않는다 |
| 3 | 옛 `herdr` TUI가 없는지 | `Get-Command herdr -ErrorAction SilentlyContinue` (출력 없음이 정상) | **사용자 확인.** 앱과 다른 서버를 쓰므로 쓰지 않는다. 지울지는 사용자가 정한다 |
| 4 | Node.js | `node --version` | **사용자 조치.** `winget install OpenJS.NodeJS.LTS` |
| 5 | Codex CLI | `Get-Command codex` | `npm i -g @openai/codex@latest` |
| 6 | Antigravity CLI | `agy --version` | **사용자 조치.** Antigravity 앱을 설치하고 앱 안내에 따라 `agy`를 PATH에 등록 |
| 7 | Playwright | `npx --no-install playwright --version` (없으면 설치를 묻지 않고 실패한다) | 프로젝트 폴더에서 `npm i -D playwright` 후 `npx playwright install chromium` |
| 8 | 로그인 | `agy models` (모델 목록). Codex는 사용자에게 묻는다 | **사용자 조치.** 별도 터미널에서 `codex`, `agy`를 한 번씩 실행해 로그인 |
| 9 | Codex 권한 모드 | `Get-Content .hc\local.env -ErrorAction SilentlyContinue` | macOS 9단계와 같다. 사용자가 승인했으면 `Set-Content -Encoding ASCII .hc\local.env 'CODEX_MODE=bypass'` |
| 10 | 하위 터미널 기동 | `powershell -NoProfile -ExecutionPolicy Bypass -File .hc\up.ps1; "exit=$LASTEXITCODE"` (`exit=0`, 둘 다 `idle`) | 아래 "문제 해결". **첫 실행은** 폴더 신뢰 창 때문에 `exit=1`이 정상이다. 샌드박스 모드의 Codex는 이어서 권한 선택 창(`Update Model Permissions`)을 띄우는데, 상태가 `idle`로 보여도 스크립트가 화면 문구로 감지해 멈춘다. 사용자가 직접 고른다. Full Access를 고를 거라면 처음부터 9단계의 `CODEX_MODE=bypass`로 띄운다 |
| 11 | 통신 확인 | Antigravity에게 `task.ps1 send`로 `$env:HC_TERMINAL_ID` 출력 같은 짧은 작업을 보내고(`.hc/docs/lead.md` 3절) `task.ps1 wait`가 0인지 본다 | `hc read <접두사>-agy --lines 100`으로 화면을 보고 사용자에게 보고. 승인 창이 뜨면 `.hc/agy-settings.win.json`에 필요한 명령을 추가할지 사용자에게 묻는다 |
| 12 | 브라우저 확인 | Antigravity에게 `브라우저: 필요`, `대상 URL: https://example.com`으로 Playwright 스크립트를 `.hc/qa/<작업ID>/`에 만들어 `page.title()`이 `Example Domain`인지 확인하고 스크린샷을 저장하게 한다. 본문에는 그 문구가 없을 수 있으므로 제목으로 판정한다 | 실패하면 화면을 사용자에게 보고 |

#### 기동 스크립트 문제 해결 (공통)

`up.sh`/`up.ps1`이 경고하고 `exit 1`로 끝나면 경고에 나온 대상의 화면을 `hc read <이름> --lines 60`으로 읽는다(두 OS 같음).

| 화면 | 처리 |
|---|---|
| `Trust this folder?` 같은 폴더 신뢰 창, Codex `Update Model Permissions` 권한 선택 창 | 키를 대신 누르지 않는다. 사용자가 그 터미널에서 직접 고른 뒤 스크립트를 다시 실행한다 |
| 명령 실행 권한 창 | 키를 대신 누르지 않는다. 사용자에게 고르게 한다 |
| 로그인 화면 | 로그인 단계로 돌아가 사용자에게 요청한다 |
| 업데이트 안내처럼 무해한 창 | `esc`로 넘긴 뒤 스크립트를 다시 실행한다 |
| `필요한 명령 없음: <명령>` | 해당 설치 단계로 돌아간다 |
| `하위 터미널이 여러 개입니다` | 자기가 만든 것인지 확인하고, 사용자 확인 후 하나만 남긴다 |
| `역할 불일치`·`작업 폴더 불일치` | 같은 이름을 다른 용도로 쓰고 있는 것이다. 사용자에게 보고한다 |
| 그 밖의 오류 | 화면 내용을 그대로 사용자에게 보고한다 |

## 사용법

1. 이 폴더에서 **Herdr 앱 안의 터미널**로 Claude Code를 실행한다.
2. Claude에게 일을 시키면 Claude가 설계·계약을 정하고, 필요할 때 기동 스크립트로 Codex·Antigravity를 띄워 `[hc-task]`로 나눠 맡긴다.
3. "Codex에게 시켜", "Antigravity한테 화면 만들고 브라우저로 확인시켜"처럼 말해도 된다. Claude가 보고를 받아 실제 파일·스크린샷을 확인한 뒤 요약해 준다.
4. 새 프로젝트에 복사했으면 `AGENTS.md` 5절 "프로젝트별 설정"에 기술 스택과 담당 영역을 채운다.

상태 확인:

```bash
# macOS
hc ls | jq -r --arg me "$HC_TERMINAL_ID" '.terminals[] | select(.parent==$me) | "\(.address) \(.name) \(.agent) \(.status // "-")"'
```

```powershell
# Windows
hc ls --json | ConvertFrom-Json | ForEach-Object terminals | Where-Object parent -eq $env:HC_TERMINAL_ID
```

## 레이아웃 (macOS: bercail, Windows: 기본)

macOS의 Herdr.app에서는 커뮤니티 레이아웃 **bercail**(작성자 simoncrypta)을 쓸 수 있습니다. Windows의 Herdr 앱은 기본 레이아웃을 그대로 씁니다. 레이아웃은 협업 기능에 영향이 없습니다.

1. Herdr.app을 연다.
2. <https://herdr.dev/layouts>에서 **bercail**의 복사 버튼으로 설치 문장을 복사해 Herdr 안의 에이전트에게 붙여 넣는다. `~/.config/herdr-app/layouts/bercail.json`과 mod가 추가된다.
3. `ctrl-shift-l`로 bercail을 고른다. 다크 모드는 `~/.config/herdr-app/settings.json`에 `"appearance": "dark"`.

되돌리기: `ctrl-shift-l`로 원래 레이아웃을 고른다. 화면이 깨지면 `ctrl-alt-shift-escape`로 기본 레이아웃으로 복구한다.

## ⚠️ Codex 권한 모드

기동 스크립트는 Codex를 **기본으로 샌드박스 모드**(`-s workspace-write -a never`, 네트워크 허용, herdr-core 소켓 폴더 쓰기 허용)로 띄웁니다. 샌드박스에서는 `.git/` 등이 읽기 전용이므로 공유 파일은 `.hc/`에 둡니다.

권한 우회 모드(`--dangerously-bypass-approvals-and-sandbox`)는 git에 올리지 않는 `.hc/local.env`에 `CODEX_MODE=bypass` 한 줄이 있을 때만 씁니다. 이 모드에서는 `AGENTS.md`의 담당 파일·삭제 금지 규칙이 **에이전트의 약속일 뿐 도구로 막히지 않습니다.** 프로젝트마다 따로 판단해서 켭니다.

## 검증 범위

- `.hc/up.sh`(macOS)는 가짜 `hc`로 재사용·불일치·중복·주입값·대기 시간 초과 등을 모의 검사했고, 실제 Herdr.app에서 Codex·Antigravity 기동, `hc` 보고, ego lite 브라우저 검증을 확인했습니다.
- `.hc/up.ps1`·`.hc/task.ps1`(Windows)은 Windows 11 + PowerShell 5.1 + Herdr 앱에서 기동, Codex 백엔드 작업, Antigravity 화면 구현과 Playwright 검증, 보고 파일과 `hc send` 보고를 확인했습니다. 진행 기록과 문제점·해결은 [`docs/windows-setup-issues.md`](docs/windows-setup-issues.md)에 있습니다. Windows의 `HC_TERMINAL_SOCKET`은 named pipe입니다.
- 아직 확인하지 못한 것: 샌드박스 모드 Codex 안에서 named pipe로 `hc send`가 되는지(Full Access로만 확인), 권한 창 감지·Codex argv 판정의 Windows 실환경 동작(macOS에서만 확인).
