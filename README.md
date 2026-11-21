# Herdr Agent Team: Claude · Codex · Antigravity multi-agent setup

**English** | [한국어](README.ko.md)

> **Work in Progress · 개발 진행 중**
>
> This public project is under active development and is not a stable release. Some workflows have been tested on real Windows and macOS machines; other automation is still being implemented or validated. Behaviour can vary with your environment and tool versions. Review permission settings and launch/task scripts before using it on a real project. See [verification scope](#what-has-been-verified) for tested and untested features.

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
| `AGENTS.md` | Shared rules every agent reads each session: roles, ownership, reporting, safety, per-project settings |
| `CLAUDE.md` | Claude Code notes; imports `@AGENTS.md` and `@.hc/docs/lead.md` |
| `.hc/docs/lead.md` | Claude-only procedure: start-up, dispatch/wait/exit codes, `hc` commands, OS differences, Codex/agy permissions |
| `.hc/docs/browser-qa.md` | Browser QA rules; the task scripts add a read-this-first line to tasks marked `브라우저: 필요` |
| `.hc/up.sh` | macOS: start or check the Codex and Antigravity child terminals |
| `.hc/up.ps1` | Windows: same job as `up.sh`, in PowerShell |
| `.hc/hc.ps1` | Windows: shared helpers for `up.ps1` and `task.ps1` (not run directly) |
| `.hc/agy-settings.*.json` | Per-session allow list passed to `agy --settings`; defaults only allow report messaging. Browser/Node execution may need approval |
| `.hc/task.sh`, `.hc/task.ps1` | Send a task, wait for it, and verify the report file; re-prompt the agent if it stopped without reporting |
| `.hc/tasks/` | Sent task texts and wait state (git-ignored) |
| `.hc/scope.mjs`, `.hc/scope.test.mjs` | Shared Node 18+ ownership reservations, change checks, retry limits, verified records and mock tests; no external packages |
| `.hc/local.env` | Local-only settings (git-ignored). `CODEX_MODE=bypass` runs Codex without its sandbox |
| `.hc/reports/`, `.hc/qa/` | Agent reports and browser evidence (git-ignored) |
| `.hc/art/` | Default generated-image output (git-ignored) |
| `docs/windows-setup-issues.md` | Windows setup log, issues and fixes (Korean) |
| `docs/automation-validation.md` | Actual, mock and unexecuted automation checks (Korean) |
| `docs/public-readiness.md` | Public-repository audit, permission changes and remaining limitations (Korean) |
| `LICENSE` | MIT license for this repository's code and documentation |

## Quick start

Install the Herdr app, open **a terminal inside the Herdr app** in this folder, start `claude`, and paste:

```text
Follow "Agent setup procedure" in README.ko.md for the current OS, step by step, to set up this folder's multi-agent environment.
Run each check first and skip steps that already pass. Ask me before any step marked "사용자 확인" (user confirmation).
When done, summarise each step as done / skipped / needs user action in a table.
```

Installing Herdr and logging in to Claude Code, Codex and `agy` must be done by a person.

### First-run checklist

| Step | Action |
|---|---|
| 1. Check prerequisites | Check Git, Node (`node --version`), your shell and each CLI version. Scope checks require Node 18+; prefer a supported LTS and check each tool's own requirements. macOS also needs Bash and jq; Windows scripts use PowerShell |
| 2. Install Herdr | Use the [official Herdr app](https://herdr.dev/), then check `hc --version` inside an app terminal |
| 3. Install agents and sign in | Follow the official [Claude Code](https://code.claude.com/docs/en/setup), [Codex CLI](https://developers.openai.com/codex/cli/) and [Antigravity](https://antigravity.google/download) instructions. Check `claude --version`, `codex --version`, `agy --version`; complete login yourself. If PowerShell blocks npm/Codex scripts, use `npm.cmd`/`codex.cmd` |
| 4. Configure your project | Copy tracked template files from a clean checkout, including the tracked `.hc/` files. Do not copy `.git`, local settings, agent credentials, reports or browser sessions from an existing workspace. Keep your project manifests; fill in `AGENTS.md` section 5 with stack, role boundaries, contracts and test commands |
| 5. Start agents | Start Claude inside a Herdr terminal in the project folder. Claude runs the appropriate launcher when delegation is needed; small tasks can stay with Claude |
| 6. Check messaging and permissions | Follow the [dispatch procedure](.hc/docs/lead.md). Start with a read-only task using `담당 파일: 없음`, then check its report and terminal state. Handle trust, login and permission dialogs yourself; keep sandbox defaults |
| 7. Run a small check | Run `node --test .hc/scope.test.mjs` and record pass/fail/skip. Then try a small task with explicit write paths and a test command. Browser checks require the OS-specific tool and may request approval |
| 8. Begin project work | Establish shared contracts first, delegate independent file ranges, inspect real changes and test results, then record verification. Never treat `wait` success alone as feature completion |

Detailed OS check/fix tables remain in [README.ko.md](README.ko.md#에이전트용-셋팅-절차); they are not duplicated here. Install commands below are examples: inspect downloaded scripts and follow the current official instructions. Do not assume a setup tested on one machine works on every version.

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
npm.cmd i -g @openai/codex@latest
# Antigravity app → register the agy CLI
npm.cmd i -D playwright
npx.cmd playwright install chromium                           # in the project
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

Bypass requires explicit user approval and a record in `AGENTS.md` section 5. Do not commit `.hc/local.env` or widen global permissions. Antigravity defaults only allow `hc send`; broad Node/browser command permissions are opt-in after reviewing the scripts and browser access. See [permission settings](.hc/docs/lead.md#5-권한-설정). Approval prompts may still occur, and an allow list is not a security boundary by itself.

Keep API keys, authentication files, `.env`, browser profiles and sensitive logs out of Git. `.gitignore` preserves `.env.example`/`.env.sample`/`.env.template` for placeholders only; it does not remove previously tracked files or history. Review `git status` and staged diffs before publishing. The [public-readiness audit](docs/public-readiness.md) records what was checked and what remains outside its scope.

## What has been verified

- `.hc/up.sh` (macOS) was tested against a fake `hc` and in real Herdr.app runs (agent start-up, `hc` reports, ego lite browser checks).
- `.hc/up.ps1` and `.hc/task.ps1` (Windows) were run on Windows 11 + PowerShell 5.1 + the Herdr app: start-up, a Codex backend task, an Antigravity UI task with Playwright checks, and report files plus `hc send` reports. Notes and fixes are in [`docs/windows-setup-issues.md`](docs/windows-setup-issues.md) (Korean). On Windows `HC_TERMINAL_SOCKET` is a named pipe.
- Sandboxed Codex reporting over a Windows named pipe and blocked-state handling were checked in the Todo project ([record](docs/windows-setup-issues.md)). The [automation validation record](docs/automation-validation.md) separates actual, mock and unexecuted checks: 27 core tests, 43 backend tests and two browser viewports passed in the recorded Windows environment. These are environment-specific results, not a cross-version guarantee.
- The latest task automation has not been run on real macOS; Git Bash `bash -n` was a syntax check only. Image-generation concurrency has not been tested. Earlier browser runs used an expanded allow list; unattended browser execution with the new restricted defaults has not been validated and may require approval.

## Task dispatch and verification

Small tasks can be handled by the lead alone; independent write ranges can run in parallel. With Node 18+, the task scripts reserve and compare write ranges before dispatch. `wait` means a report arrived; after reviewing files and tests, the lead uses `check` and `verify`. Corrections use `--fix-of` with at most three follow-ups per task family. See the [dispatch procedure](.hc/docs/lead.md) for path syntax and limitations. One lead must issue reservations sequentially: the shared-folder checker cannot identify who made a change or safely arbitrate concurrent reservation calls.

## Template direction

The long-term goal is a reusable open-source development-team template for Windows and macOS. Keep project-specific stack, contracts and role settings in `AGENTS.md` section 5; preserve the `.hc/` structure and `[hc-task]`/`[hc-report]` protocol.

- **Implemented:** role-based dispatch, report recovery, ownership checks, task-family retry limits and separate verification records. Claude follows the documented procedure; this is not an always-running autonomous scheduler.
- **Developing and validating:** cross-version setup, current macOS task execution, permission choices and reproducible integration checks.
- **Long-term direction:** improve Claude-led selective delegation, Codex/Antigravity collaboration, feedback/retries, integration validation, file ownership and image/development concurrency. These are development goals, not a claim that every scenario is complete or reliable today.

## License and external tools

This repository's code and documentation use the [MIT License](LICENSE). Herdr, Claude Code, Codex, Antigravity, ego lite and other external tools retain their own licenses and service terms; this repository does not redistribute them. The optional bercail layout is credited above and is not bundled. Check provenance and license compatibility before contributing external code or assets.
