# Herdr Agent Team: Claude · Codex · Antigravity multi-agent setup

**English** | [한국어](README.ko.md)

A shared project-folder template for running three coding agents inside [Herdr](https://herdr.dev). **Claude Code is the lead and core engineer**; it starts **Codex** (backend implementation) and **Antigravity** (`agy`, UI implementation and browser verification) in neighbouring terminals and exchanges work with them through a fixed message format. Nothing depends on the project name, so copy the files into any new project. Works on **macOS and Windows**.

```
User ──▶ Claude (lead + schema, auth, shared types, integration)
           ├─ [hc-task] ─▶ Codex       (<prefix>-codex)  backend APIs, logic, integrations, tests
           └─ [hc-task] ─▶ Antigravity (<prefix>-agy)    screens, forms, API wiring + browser E2E
               ◀─ [hc-report] ─┘
pi: the user's personal agent (not part of development)
```

## Roles

| Agent | Writes | Owns |
|---|---|---|
| **Claude** | DB schema and migrations, auth and security, shared types / API contracts / error format, integration glue | Design, task split, integration review |
| **Codex** | Spec'd feature APIs and service logic, external integrations, backend tests, large refactors | API behaviour and data integrity |
| **Antigravity** | Screens, components, forms, state binding, API wiring, loading/error states, environment and build scripts | User flows verified in a real browser |
| **art** | Image generation, on demand: a `<prefix>-art` terminal running Codex or Antigravity, chosen by the user for each image | Only writes image files to the given path |
| **pi** | Personal work | Excluded from the development split |

Shared rules (roles, ownership, reporting, safety) live in [`AGENTS.md`](AGENTS.md); Claude's dispatch procedure is in [`.hc/docs/lead.md`](.hc/docs/lead.md) and the browser QA rules in [`.hc/docs/browser-qa.md`](.hc/docs/browser-qa.md) (all in Korean).

## macOS vs Windows

| | macOS | Windows |
|---|---|---|
| Herdr | **Herdr app** + herdr-core (`hc`) | **Herdr app** + herdr-core (`hc`) |
| Messaging | `hc send` / `hc wait` / `hc read` | same |
| Own address | `$HC_TERMINAL_ID` (e.g. `t2c`) | `$env:HC_TERMINAL_ID` |
| Scripts | `.hc/up.sh`, `.hc/task.sh` (bash, needs `jq`) | `.hc\up.ps1`, `.hc\task.ps1`, `.hc\hc.ps1` (PowerShell) |
| Layout | bercail (optional) | default |
| Browser QA | ego lite (`ego-browser`) | Playwright |

Both use the same Herdr app and `hc` commands; the message format (`[hc-task]` / `[hc-report]`), roles and rules are identical. Only the script language, layout and browser tool differ.

## Files

| File | Purpose |
|---|---|
| `AGENTS.md` | Short shared rules every agent reads each session (~75 lines): roles, ownership, reporting, safety, per-project settings |
| `CLAUDE.md` | Claude Code notes; imports `@AGENTS.md` and `@.hc/docs/lead.md` |
| `.hc/docs/lead.md` | Claude-only procedure: start-up, dispatch/wait/exit codes, `hc` commands, OS differences, Codex/agy permissions |
| `.hc/docs/browser-qa.md` | Browser QA rules; the task scripts add a read-this-first line to tasks marked `브라우저: 필요` |
| `.hc/up.sh` | macOS: start or check the Codex and Antigravity child terminals |
| `.hc/up.ps1` | Windows: same job as `up.sh`, in PowerShell |
| `.hc/hc.ps1` | Windows: shared helpers for `up.ps1` and `task.ps1` (not run directly) |
| `.hc/agy-settings.*.json` | Per-session allow list passed to `agy --settings`, so report and browser commands run without approval prompts |
| `.hc/task.sh`, `.hc/task.ps1` | Send a task, wait for it, and verify the report file; re-prompt the agent if it stopped without reporting |
| `.hc/tasks/` | Sent task texts and wait state (git-ignored) |
| `.hc/scope.mjs`, `.hc/scope.test.mjs` | Node 18+ 공통 소유 범위 예약·변경 검사·수정 지시 한도·verified 기록과 모의 테스트(외부 패키지 없음) |
| `.hc/local.env` | Local-only settings (git-ignored). `CODEX_MODE=bypass` runs Codex without its sandbox |
| `.hc/reports/`, `.hc/qa/` | Agent reports and browser evidence (git-ignored) |
| `docs/windows-setup-issues.md` | Windows setup log, issues and fixes (Korean) |

## Quick start

Install the Herdr app, open **a terminal inside the Herdr app** in this folder, start `claude`, and paste:

```text
Follow "Agent setup procedure" in README.ko.md for the current OS, step by step, to set up this folder's multi-agent environment.
Run each check first and skip steps that already pass. Ask me before any step marked "사용자 확인" (user confirmation).
When done, summarise each step as done / skipped / needs user action in a table.
```

Installing Herdr and logging in to Claude Code, Codex and `agy` must be done by a person.

### Install summary

**macOS**
```bash
curl -fsSL https://releases.herdr.dev/app/install.sh | sh   # Herdr.app (+ herdr-core)
brew install jq
npm i -g @openai/codex@latest
# Antigravity app → register the agy CLI; ego lite app → ego-browser CLI
```
Do not use the old standalone `herdr` CLI/TUI on either OS; it talks to a different server than the Herdr app.

**Windows (PowerShell)**
```powershell
powershell -c "irm https://releases.herdr.dev/app/install.ps1 | iex"   # Herdr app (+ herdr-core)
winget install OpenJS.NodeJS.LTS
npm i -g @openai/codex@latest
# Antigravity app → register the agy CLI
npm i -D playwright; npx playwright install chromium            # in the project
```

Then start the agents (Claude does this itself when needed):

```bash
.hc/up.sh                                                            # macOS
powershell -NoProfile -ExecutionPolicy Bypass -File .hc\up.ps1       # Windows
```

## Layout (macOS: bercail, Windows: default)

On Herdr.app you can use the community layout **bercail** (by simoncrypta): copy its install prompt from <https://herdr.dev/layouts>, paste it to an agent inside Herdr, then pick it with `ctrl-shift-l`. On Windows the Herdr app keeps its default layout. The layout does not affect collaboration.

## ⚠️ Codex permission mode

The launchers start Codex **sandboxed by default** (`-s workspace-write -a never`, network on, herdr-core socket folder writable). Bypass mode (`--dangerously-bypass-approvals-and-sandbox`) is used only when the git-ignored `.hc/local.env` contains `CODEX_MODE=bypass`. In bypass mode the rules in `AGENTS.md` are promises, not enforced limits. Decide per project.

## What has been verified

- `.hc/up.sh` (macOS) was tested against a fake `hc` and in real Herdr.app runs (agent start-up, `hc` reports, ego lite browser checks).
- `.hc/up.ps1` and `.hc/task.ps1` (Windows) were run on Windows 11 + PowerShell 5.1 + the Herdr app: start-up, a Codex backend task, an Antigravity UI task with Playwright checks, and report files plus `hc send` reports. Notes and fixes are in [`docs/windows-setup-issues.md`](docs/windows-setup-issues.md) (Korean). On Windows `HC_TERMINAL_SOCKET` is a named pipe.
- 샌드박스 Codex의 named pipe 보고와 blocked 대기 구분은 Todo 테스트 프로젝트에서 확인했습니다([기록](docs/windows-setup-issues.md)). 새 자동화의 실제/모의/미실행 구분은 [자동화 검증 기록](docs/automation-validation.md)에 남깁니다. macOS에서 새 task 자동화의 실제 실행은 별도 검증이 필요합니다.

## 작업 분배와 검증

작은 작업은 단독 처리하고 독립 범위는 병렬로 맡깁니다. Node 18+가 있으면 전송 전에 쓰기 범위를 예약·비교합니다. `wait`는 보고 수신이며, 실파일·테스트 확인 후 `check`와 `verify`로 지휘자의 검증을 기록합니다. 실패 수정은 `--fix-of`로 같은 계열에 최대 3회 지시합니다. 경로 문법·명령·공유 폴더의 변경자 식별 한계는 [지휘 절차](.hc/docs/lead.md)를 따릅니다.
