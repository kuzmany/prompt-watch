# prompt-watch

**Prompts, back from the dead.**

Terminal AI agents never write the prompt you are typing to disk. Kill the
pane, crash the process, hit Ctrl+C at the wrong moment — a 500-word prompt
is gone. prompt-watch snapshots the prompt box of every agent pane in tmux
every 10 seconds, so a crash costs you nothing.

*(demo GIF coming: type a long prompt, kill the pane, Alt+G, prompt back)*

Works with **Claude Code** and **Codex CLI**. The gap is real across all
agent CLIs: none of them persist the unsent prompt
([openai/codex#23085](https://github.com/openai/codex/issues/23085) is still
open), and every existing recovery tool reads only *submitted* history.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/kuzmany/prompt-watch/main/install.sh | bash
```

Flags: `--yes` (no questions), `--key M-r` (different picker key),
`--ctrl-g` (exact-copy alias, see below), `--uninstall` (clean removal).
Needs tmux and bash ≥ 4.2 (macOS: `brew install bash`).

## Use

You learn two gestures:

- **Alt+G** — the picker pops up with your 10 most recent drafts.
  `1`–`9` picks a row, `↑`/`↓` moves, **Enter** inserts the draft back into
  the pane you came from, `c` copies it to the clipboard, `q` quits.
- **`prompt-watch doctor`** — one-line health checks when something feels off.

That's it. The daemon runs invisibly, starts itself, and survives nothing —
if it dies, the next picker open restarts it.

### Ctrl+G: the exact copy (Claude Code only)

Screen scraping reads what is visible. Ctrl+G reads the truth: Claude Code's
external-editor feature writes the real prompt buffer to a file, and the
`prompt-watch-visual` shim copies it to the clipboard without changing the
prompt. Enable with `install.sh --ctrl-g` — it aliases `claude` to set
`$VISUAL` for that command only, so `git commit` keeps your real editor.

## Supported agents

| Agent | Auto-snapshot | Exact copy (Ctrl+G) |
|---|---|---|
| Claude Code | yes | yes |
| Codex CLI | yes | no equivalent found yet |

Adding an agent is one process-name row plus one composer parser
(`parse_box_*` in `bin/prompt-watch`) — PRs welcome, fixtures included.

## How it works

1. One daemon wakes every 10 s and lists tmux panes once.
2. Panes running an agent whose window was active in the last 10 minutes get
   captured; an untouched pane cannot be growing a draft.
3. A per-agent parser extracts the prompt box (Claude: the region between
   the last two horizontal rules opening with `❯`; Codex: the trailing `›`
   block).
4. Changed text of 15+ characters is saved. A draft that extends the pane's
   last snapshot — or any recent stored draft — overwrites that entry
   instead of duplicating it.
5. The newest 200 drafts are kept as plain files in
   `~/.local/state/prompt-watch/`.

## Honest limits

- tmux only. Without a pane there is nothing to read.
- A draft typed and lost inside one 10 s interval is never seen.
- Only the visible part of the box; a soft wrap is indistinguishable from a
  real newline, and a blank line ends the Codex block.
- Pasted blocks render as `[Pasted text #N]`, so scraping cannot recover
  them (Claude Code keeps the bytes in `~/.claude/paste-cache/`).
- Claude Code's dim ghost suggestions can be captured as if you typed them.
- Drafts are plaintext — same exposure as your shell history.

## Config

<details>
<summary>Environment variables (defaults are fine)</summary>

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

## Prior art

[Lua2147/claude-toolkit-catalog](https://github.com/Lua2147/claude-toolkit-catalog)
ships a capture-pane watcher with grep-based recovery — the only other tool
we found that goes after the *unsent* buffer. Everything else reads
`history.jsonl`, i.e. prompts you already sent.

## License

MIT
