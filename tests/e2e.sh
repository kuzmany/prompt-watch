#!/usr/bin/env bash
# Live end-to-end test (needs tmux; run locally, not in CI).
#
# Boots fake claude and codex panes in a scratch tmux session - each prints a
# realistic prompt box, then execs a copied /bin/sleep so pane_current_command
# reports the agent's name - and asserts that an isolated daemon captures both
# drafts within one interval. PW_DIR isolation also disables the daemon's
# process-table guard, so this runs fine next to a production daemon.

set -euo pipefail

PW="$(cd "$(dirname "$0")/.." && pwd)/bin/prompt-watch"
tmp=$(mktemp -d)
session=pwe2e
export PW_DIR="$tmp/drafts" PW_INTERVAL=2

cleanup() {
	tmux kill-session -t $session 2>/dev/null || true
	if [[ -r $PW_DIR/.daemon.pid ]]; then
		kill "$(cat "$PW_DIR/.daemon.pid")" 2>/dev/null || true
	fi
	rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$PW_DIR"
cp /bin/sleep "$tmp/bin/claude"
cp /bin/sleep "$tmp/bin/codex"

NB=$'\xc2\xa0'
RULE=$(printf '─%.0s' {1..90})
CLAUDE_DRAFT="e2e claude draft that must be captured by the daemon"
CODEX_DRAFT="e2e codex draft that must be captured by the daemon"

cat >"$tmp/claude-boot.sh" <<EOF
printf '%s\n' "some scrollback"
printf '%s\n' "$RULE"
printf '❯$NB%s\n' "$CLAUDE_DRAFT"
printf '%s\n' "$RULE"
printf '  status line\n'
exec "$tmp/bin/claude" 60
EOF

cat >"$tmp/codex-boot.sh" <<EOF
printf '%s\n' "some scrollback"
printf '› %s\n' "$CODEX_DRAFT"
printf '\n'
printf '  status line\n'
exec "$tmp/bin/codex" 60
EOF

tmux kill-session -t $session 2>/dev/null || true
tmux new-session -d -s $session -x 100 -y 30 "bash $tmp/claude-boot.sh"
tmux new-window -t $session "bash $tmp/codex-boot.sh"

"$PW" daemon &
sleep 5

fail=0
if grep -rqsF "$CLAUDE_DRAFT" "$PW_DIR"; then
	echo "ok    claude draft captured"
else
	echo "FAIL  claude draft not captured"
	fail=1
fi
if grep -rqsF "$CODEX_DRAFT" "$PW_DIR"; then
	echo "ok    codex draft captured"
else
	echo "FAIL  codex draft not captured"
	fail=1
fi

((fail)) && exit 1
echo PASS
