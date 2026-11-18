# Herdr Agent Team: Multi-Agent Setup on Herdr

**English** | [한국어](README.ko.md)

A drop-in project template for running three coding agents together inside the [Herdr](https://herdr.dev) app. **Claude Code is the orchestrator.** It starts **Codex** (implementation and verification) and **pi** (browser QA tester: checks real screens with ego lite) as child terminals and exchanges tasks and reports with them through the `hc` CLI. Nothing depends on the project name, so you can copy the files into any project.

```
You ──▶ Claude (orchestrator)
          ├─ hc send ─▶ Codex (<prefix>-codex)   implement · test · debug
          └─ hc send ─▶ pi    (<prefix>-pi)      browser QA (ego lite)
              ◀─ [hc-report] ─┘
```

> The agent rules (`AGENTS.md`, `CLAUDE.md`) are written in Korean and tell the agents to answer in Korean. See [Customize it](#customize-it) to change that.

## Quick start: let an agent set it up

Install the Herdr app, start Claude Code (`claude`) in this folder from a **terminal inside Herdr**, and paste the prompt below. You still install and sign in to Herdr and Claude Code yourself (see [section 1](#1-install-the-tools)).

```text
Run the "Agent setup steps" in README.md from top to bottom to set up the multi-agent environment in this folder.
Run each step's check first and skip the step if it already passes. Ask me before any step marked "ask the user".
When you finish, give me a table of each step's result (done / skipped / needs your action).
```

### Agent setup steps

> This section is for the agent doing the setup (Claude Code). Run each step as **check → act if the check fails → check again**. If the check passes, skip the action. If a step fails, don't go on: report the cause and the output to the user.
>
> Never do these on the user's behalf: interactive sign-ins (first run of `claude`/`codex`/`pi`), key presses in trust or permission dialogs, `sudo` commands, approving bypass mode. Stop at those steps and tell the user exactly what to do. For commands the user must run, tell them to type `! <command>` at the prompt.

| # | Step | Check (passes when) | Action (if the check fails) |
|---|---|---|---|
| 1 | Running inside Herdr | `echo "$HC_TERMINAL_ID"` (not empty) | **Stop.** Ask the user to restart `claude` from a terminal inside the Herdr app |
| 2 | herdr-core (`hc`) | `hc --version` (prints a version) | **Ask the user**, then `curl -fsSL https://releases.herdr.dev/core/install.sh \| sh`. Never run bare `hc` |
| 3 | jq | `command -v jq` | `brew install jq` |
| 4 | Codex CLI | `command -v codex` | `npm i -g @openai/codex@latest` |
| 5 | pi | `command -v pi` | `npm i -g @earendil-works/pi-coding-agent` |
| 5-1 | ego lite (pi's browser) | `command -v ego-browser && ego-browser --version` | **User action.** Have the user install the ego lite app and finish its first-run onboarding, which adds `~/.local/bin/ego-browser`. If the command isn't found, run `export PATH="$HOME/.local/bin:$PATH"` and check again |
| 6 | npm permission error | Did step 4 or 5 fail with `EACCES` or "root-owned files"? | **Ask the user** to run `! sudo chown -R "$(id -u):$(id -g)" ~/.npm` themselves, then redo steps 4–5 |
| 7 | Codex and pi sign-in | Ask the user whether they've signed in (the agent can't check) | **User action.** Tell them to run `codex` and `pi` once each in a separate terminal and sign in |
| 8 | Codex permission mode | `grep -n 'dangerously-bypass' .hc/up.sh` and the approval record in section 4 of `AGENTS.md` | **Ask the user** whether to keep bypass mode or switch to the sandbox. For the sandbox, replace the launch line in `.hc/up.sh` with the one in [the section below](#️-codex-runs-in-bypass-mode) and rewrite the approval record in `AGENTS.md` section 4 to match |
| 9 | Start child terminals | `.hc/up.sh; echo "exit=$?"` (`exit=0`, Codex and pi are `idle`) | Follow "Fixing `up.sh`" below |
| 10 | Messaging works | Send pi a short `[hc-task]` (for example `echo ok`) and check that an `[hc-report]` comes back (format in `AGENTS.md` section 2-2) | If no report arrives, look at `hc read <target> --lines 100 --json` and report to the user |
| 10-1 | pi's browser works | Send pi an `[hc-task]` to read `ego-browser skill` and report the title of `https://example.com` from `taskSpace("qa-smoke")` (`대상 URL: https://example.com`) | If it fails, report pi's screen to the user. Also ask whether pi's model accepts images (if not, visual checks are reported as unverified) |
| 11 | (Optional) bercail theme | `test -f ~/.config/herdr-app/layouts/bercail.json` | **Ask the user.** If they want it, walk them through [section 2](#2-install-the-theme-layout-bercail) (they copy the install line from herdr.dev) |

#### Fixing `up.sh`

If `up.sh` warns and exits with code 1, look at the terminal it names with `hc read <name> --lines 60`, then:

| Screen | What to do |
|---|---|
| A folder trust dialog such as `Trust this folder?` (common on Codex's first run) | Don't press keys for the user. Ask them to choose in that terminal, then run `.hc/up.sh` again |
| A sign-in screen | Go back to step 7 and ask the user to sign in |
| A harmless notice, such as an update prompt | Press `esc` to dismiss it, then run `.hc/up.sh` again |
| `경고: 필요한 명령 없음: <command>` (missing command) | Go back to the matching step, 2–5 |
| `하위 터미널이 여러 개입니다` (several child terminals) | Check that you created them, ask the user, then keep one (`hc kill <name>`) |
| Any other error, or `error` state | Report the screen contents to the user as they are |

## Files

| File | Purpose |
|---|---|
| `AGENTS.md` | Shared rules for all three agents: roles, the `hc` protocol (task and report formats), file ownership, safety rules |
| `CLAUDE.md` | Claude Code notes. Imports `@AGENTS.md` |
| `.hc/up.sh` | Starts the Codex and pi child terminals, or checks the ones already running |
| `.hc/reports/` | Agent reports (ignored by git) |
| `.hc/qa/` | Screenshots and evidence from pi's browser checks (ignored by git) |

## 1. Install the tools

These steps are for macOS on Apple silicon.

### Herdr app and herdr-core (`hc`)

```bash
# Herdr app (installs herdr-core too if it is missing)
curl -fsSL https://releases.herdr.dev/app/install.sh | sh
# or download https://releases.herdr.dev/app/Herdr.dmg and move it to Applications

# herdr-core only, or to update it
curl -fsSL https://releases.herdr.dev/core/install.sh | sh
hc update
```

Check the install:

```bash
hc --version          # e.g. hc 0.1.20
hc --help             # command list (don't run bare `hc`: it opens a terminal picker)
```

> Don't use the old `herdr agent ...` / `herdr pane ...` commands. They talk to a different server that the app doesn't show. Always use `hc`.

### Agent CLIs and tools

```bash
brew install jq                                   # used by up.sh
npm i -g @anthropic-ai/claude-code                # Claude Code
npm i -g @openai/codex@latest                     # Codex CLI
npm i -g @earendil-works/pi-coding-agent          # pi
```

Sign in to each CLI once by running `claude`, `codex` and `pi`.

### ego lite (pi's browser)

pi drives a browser through the `ego-browser` CLI of the **ego lite app** (a Chromium browser built for agents). Install the app and finish its first-run onboarding; that registers `~/.local/bin/ego-browser`.

```bash
command -v ego-browser   # ~/.local/bin/ego-browser
ego-browser --version    # e.g. ego-browser 0.6.3.17
ego-browser skill        # agent usage guide (pi reads it before each task)
```

> ego lite uses the real accounts you're signed in to. That's why `AGENTS.md` limits pi to the `대상 URL:` (target URL) in each task and forbids writes on live services (payments, deletes, posts and so on).

> If npm fails with `EACCES` or "cache folder contains root-owned files", fix the cache owner with `sudo chown -R "$(id -u):$(id -g)" ~/.npm`.

## 2. Install the theme (layout): bercail

The screen uses **bercail**, a Herdr community layout by simoncrypta. It has spaces and an agent list in the left sidebar and a desk of agent terminals in the middle. This repo doesn't include bercail's files. You install the author's shared copy from inside Herdr.

1. Open the Herdr app.
2. In a browser, open <https://herdr.dev/layouts> and find **bercail**.
3. Use the entry's copy button and paste the line to an agent running inside Herdr (for example Claude Code). The agent adds `~/.config/herdr-app/layouts/bercail.json` and the mods it needs (`mods/bercail-agents/`, `mods/bercail-desk/`). Your current layout stays as it is.
4. Press `ctrl-shift-l` and pick bercail.
5. For dark mode, set `"appearance": "dark"` in `~/.config/herdr-app/settings.json`.

To undo, press `ctrl-shift-l` and pick your old layout. If the window breaks, press `ctrl-alt-shift-escape` to reset to the default layout and keys. To edit layouts and mods yourself, see `~/.config/herdr-app/AGENTS.md`, which Herdr writes.

## 3. Usage

1. Clone or copy this repo, then start Claude Code from a **terminal inside the Herdr app**:

   ```bash
   echo $HC_TERMINAL_ID   # should print an address like t2c; empty means you're outside Herdr
   claude
   ```

2. When Claude needs help, it runs `.hc/up.sh` to start the child terminals.
   - Names are `<prefix>-codex` and `<prefix>-pi`, where the prefix is the normalized folder name (`.hc/up.sh --prefix` prints it).
   - If they are already running, it starts nothing and checks their folder, role and status. If something is wrong, it warns and exits with code 1.
   - Only Claude runs `up.sh`. If Codex or pi runs it, a duplicate set of child terminals appears.
3. Say things like "have Codex do it" or "ask pi to check it in the browser". Claude sends an `[hc-task]` in the format from `AGENTS.md`, gets an `[hc-report]` back, checks the result and summarizes it for you.

Check status:

```bash
hc ls | jq -r --arg me "$HC_TERMINAL_ID" \
  '.terminals[] | select(.parent==$me) | "\(.address) \(.name) \(.agent) \(.status // "-")"'
```

## ⚠️ Codex runs in bypass mode

`.hc/up.sh` starts Codex with `--dangerously-bypass-approvals-and-sandbox`: no approval prompts and no sandbox. The original author chose this for their own machine. **Decide whether it fits yours before you use it.**

- In this mode Codex can edit any file and run any command. Rules in `AGENTS.md`, such as owned files and no deleting, are promises the agents keep. **No tool enforces them.**
- To use a sandbox instead, replace the Codex line in `.hc/up.sh` with:

  ```sh
  exec codex --no-daemon -s workspace-write -a never \
    -c "sandbox_workspace_write.network_access=true" \
    -c "sandbox_workspace_write.writable_roots=[\"$HOME/.local/state/herdr-core\"]" \
    -c "shell_environment_policy.set.HC_TERMINAL_ID=\"$HC_TERMINAL_ID\"" \
    -c "shell_environment_policy.set.HC_TERMINAL_SOCKET=\"$HC_TERMINAL_SOCKET\""
  ```

  In sandbox mode `.agents/`, `.codex/` and `.git/` are read-only, so keep shared files in `.hc/`. The Codex address check in `up.sh` keeps working.

## Customize it

This repo is a **starting point** shaped around one person's workflow. Adapt it to your own setup instead of using it as is.

- **Roles:** change each agent's role, specialty and pi's forbidden list in the table in section 1 of `AGENTS.md`. You can drop an agent (for example, run without pi) or add one.
- **Agents and launch flags:** edit the `codex`/`pi` launch lines, the `command -v` list and the role names in `.hc/up.sh`. To add another CLI agent, add a launch line and match the role check in `check_terminal` (`status.app`).
- **Permission level:** run Codex in a sandbox (see above), or keep bypass mode only inside an isolated environment. **Rewrite the approval record in section 4 of `AGENTS.md` with your own decision.**
- **Language:** `AGENTS.md` and `CLAUDE.md` say "answer everything in Korean". Change that line for another language, or translate the files.
- **Report format and folder:** you can change the `[hc-task]`/`[hc-report]` fields and the report path (`.hc/reports/`) to match your team. Edit only `AGENTS.md`, which holds the shared rules.
- **Theme:** the default Herdr layout or any other layout from herdr.dev works just as well. The theme doesn't affect collaboration.

## What was tested

`.hc/up.sh` was tested against a fake `hc`: reuse, folder/role/status mismatch, duplicate terminals, wrong Codex address, malformed `hc ls` output, fresh start, and waits that return early on a message or time out. Startup races, cleanup of child terminals when the parent exits, and end-to-end message delivery were not tested in a real environment.
