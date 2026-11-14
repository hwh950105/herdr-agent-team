# Herdr Agent Team: Multi-Agent Setup on Herdr

**English** | [한국어](README.ko.md)

A drop-in project template for running three coding agents together inside the [Herdr](https://herdr.dev) app. **Claude Code is the orchestrator.** It starts **Codex** (implementation and verification) and **pi** (helper: search, lint, running tests) as child terminals and exchanges tasks and reports with them through the `hc` CLI. Nothing depends on the project name, so you can copy the files into any project.

```
You ──▶ Claude (orchestrator)
          ├─ hc send ─▶ Codex (<prefix>-codex)   implement · test · debug
          └─ hc send ─▶ pi    (<prefix>-pi)      read · search · run checks
              ◀─ [hc-report] ─┘
```

> The agent rules (`AGENTS.md`, `CLAUDE.md`) are written in Korean and tell the agents to answer in Korean. See [Customize it](#customize-it) to change that.

## Files

| File | Purpose |
|---|---|
| `AGENTS.md` | Shared rules for all three agents: roles, the `hc` protocol (task and report formats), file ownership, safety rules |
| `CLAUDE.md` | Claude Code notes. Imports `@AGENTS.md` |
| `.hc/up.sh` | Starts the Codex and pi child terminals, or checks the ones already running |
| `.hc/reports/` | Agent reports (ignored by git) |

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
3. Say things like "have Codex do it" or "ask pi to verify". Claude sends an `[hc-task]` in the format from `AGENTS.md`, gets an `[hc-report]` back, checks the result and summarizes it for you.

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
