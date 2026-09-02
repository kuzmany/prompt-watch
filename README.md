# prompt-watch

**Prompts, back from the dead.**

![prompt-watch title card: a sunset beach, a lifeguard tower, a life ring and a terminal window riding the wave](docs/media/prompt-watch-hero.jpg)

[![ci](https://github.com/kuzmany/prompt-watch/actions/workflows/ci.yml/badge.svg)](https://github.com/kuzmany/prompt-watch/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![bash](https://img.shields.io/badge/bash-%E2%89%A5%203.2-lightgrey)
![tmux](https://img.shields.io/badge/needs-tmux-brightgreen)

Your AI coding agent never saves the prompt you are typing. Crash, Ctrl+C,
closed pane — a 500-word prompt is gone. prompt-watch quietly snapshots the
prompt box of every **Claude Code** and **Codex CLI** pane in tmux, so you
can always get it back.

![Typing a long prompt in Claude Code, the process dies, Alt+G opens the picker, Enter puts the draft back](docs/media/demo.gif)

*The agent dies mid-prompt. Alt+G, Enter — it's back.*

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/kuzmany/prompt-watch/v0.1.1/install.sh | bash -s -- --yes
```

Needs tmux (`brew install tmux` / `apt install tmux`). Nothing else — it
runs on the bash your system already has, macOS 3.2 included.

Then press **Alt+G** inside tmux. That's the whole tool.

| Works on | Agents | Verified by |
|---|---|---|
| Linux | Claude Code, Codex CLI | CI: full suite + live tmux daemon |
| macOS (system bash 3.2, BSD tools) | Claude Code, Codex CLI | CI: `macos-latest` install, doctor, live daemon |
| WSL / WSL2 | Claude Code, Codex CLI | daily use by the author; clipboard falls back to `clip.exe` |
| Windows without WSL | — | no tmux, so no |

## Use

- **Alt+G** — your last 10 drafts. `1`–`9` or `↑`/`↓` picks one,
  **Enter** puts it back into the prompt, `c` copies it, `q` quits.
- Drafts of 15+ characters are captured on the next 10-second scan and kept
  as plain text in `~/.local/state/prompt-watch/` — same exposure as your shell
  history.
- Something feels off? `prompt-watch doctor` tells you what.

<details>
<summary><b>Or paste this into your agent and let it install</b></summary>

Works in Claude Code, Codex CLI, Grok CLI, or any terminal agent — it
installs prompt-watch and proves it works before it says it is done:

```text
Install prompt-watch from https://github.com/kuzmany/prompt-watch — it snapshots
the prompt box of AI agent panes in tmux so an unsent prompt survives a crash.

1. Check the prerequisite first: `tmux -V` (any version with popups, 3.2+).
   Say so and stop if tmux is missing.
2. Read https://raw.githubusercontent.com/kuzmany/prompt-watch/v0.1.1/install.sh
   before running anything, and tell me what it changes. Then install with:
   `curl -fsSL https://raw.githubusercontent.com/kuzmany/prompt-watch/v0.1.1/install.sh | bash -s -- --yes`
   Append `--ctrl-g` to that command only if I use Claude Code and want Ctrl+G
   to copy the exact prompt buffer (it adds one alias to my shell rc).
3. Run `~/.local/bin/prompt-watch doctor` and show me the output. Every line
   must be ok or info. If the daemon line says it is not running, run
   `~/.local/bin/prompt-watch ensure`, wait a second, and check again.
4. Tell me the picker key it installed (Alt+G by default) and how to change it.
   Do not modify my tmux config by hand — the installer owns that block.
5. If `~/.local/bin` is not on my PATH, tell me the exact line to add.

Then stop. Do not start the picker for me: it is interactive and I will press
Alt+G myself.
```

</details>

<details>
<summary><b>Install options</b></summary>

| Flag | Does |
|---|---|
| `--yes` | no questions asked |
| `--key M-r` | picker on a different tmux key |
| `--ctrl-g` | Ctrl+G copies the exact prompt buffer (Claude Code only) |
| `--uninstall` | clean removal; add `--purge` to also delete stored drafts |

Everything the installer writes to your dotfiles sits between
`# >>> prompt-watch >>>` markers and is removed cleanly by `--uninstall`.

</details>

<details>
<summary><b>Ctrl+G: the exact copy (Claude Code only)</b></summary>

Screen scraping reads what is visible. Ctrl+G reads the truth: Claude Code's
external-editor feature writes the real prompt buffer to a file, and the
`prompt-watch-visual` shim copies it to the clipboard without changing the
prompt. Enable with `install.sh --ctrl-g` — it aliases `claude` to set
`$VISUAL` for that command only, so `git commit` keeps your real editor.

</details>

<details>
<summary><b>How it works, and honest limits</b></summary>

1. One daemon wakes every 10 s and lists tmux panes once.
2. Panes running an agent whose window was active in the last 10 minutes get
   captured; an untouched pane cannot be growing a draft.
3. A per-agent parser extracts the prompt box (Claude: the region between
   the last two horizontal rules opening with `❯`; Codex: the trailing `›`
   block).
4. Changed text of 15+ characters is saved. A draft that extends the pane's
   last snapshot — or any recent stored draft — overwrites that entry
   instead of duplicating it.
5. The newest 200 drafts are kept as plain files.

Limits, stated plainly:

- tmux only. Without a pane there is nothing to read.
- A draft typed and lost inside one 10 s interval is never seen.
- Only the visible part of the box; a soft wrap is indistinguishable from a
  real newline, and a blank line ends the Codex block.
- Pasted blocks render as `[Pasted text #N]`, so scraping cannot recover
  them (Claude Code keeps the bytes in `~/.claude/paste-cache/`).
- Claude Code's dim ghost suggestions can be captured as if you typed them.
  Its empty-box placeholders (`Press up to edit…`, the rotating `Try "…"`) are
  filtered out; inline completions still look like typed text to a screen read.
- Drafts are plaintext — same exposure as your shell history.

Adding an agent is one process-name row plus one composer parser
(`parse_box_*` in `bin/prompt-watch`) — PRs welcome, fixtures included.

</details>

<details>
<summary><b>Config</b></summary>

| Variable | Default | Meaning |
|---|---|---|
| `PW_DIR` | `~/.local/state/prompt-watch` | draft storage |
| `PW_INTERVAL` | `10` | seconds between snapshots |
| `PW_KEEP` | `200` | drafts kept |
| `PW_IDLE` | `600` | skip windows idle longer than this (s) |
| `PW_MINLEN` | `15` | minimum draft length saved |
| `PW_SCAN` | `30` | recent drafts checked for continuation |

Hidden commands for scripts: `prompt-watch list [N]`, `show N`, `copy [N]`.

</details>

## License

MIT
