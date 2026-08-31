#!/usr/bin/env bash
# prompt-watch installer.
#
#   ./install.sh                 install (asks before touching each file)
#   ./install.sh --yes           install without questions
#   ./install.sh --key M-r       use a different tmux picker key (default M-g)
#   ./install.sh --ctrl-g        also alias `claude` so Ctrl+G copies the exact
#                                prompt buffer (Claude Code only)
#   ./install.sh --uninstall     remove the binaries and config blocks
#   ./install.sh --uninstall --purge   also delete the stored drafts
#
# Everything written to your dotfiles sits between marker comments
# (# >>> prompt-watch >>> ... # <<< prompt-watch <<<) and is removed cleanly
# by --uninstall.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/kuzmany/prompt-watch/main"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/prompt-watch"
TMUX_CONF="$HOME/.tmux.conf"
MARK_OPEN="# >>> prompt-watch >>>"
MARK_CLOSE="# <<< prompt-watch <<<"

yes=0 key="M-g" ctrl_g=0 uninstall=0 purge=0
while (($#)); do
	case $1 in
	--yes | -y) yes=1 ;;
	--key) key=${2:?--key needs a value}; shift ;;
	--ctrl-g) ctrl_g=1 ;;
	--uninstall) uninstall=1 ;;
	--purge) purge=1 ;;
	*) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 1 ;;
	esac
	shift
done

confirm() {
	((yes)) && return 0
	local a
	read -r -p "$1 [y/N] " a
	[[ $a == y || $a == Y ]]
}

# Remove our marker block from a file, in place, if present.
strip_block() {
	[[ -f $1 ]] || return 0
	grep -qF "$MARK_OPEN" "$1" || return 0
	local tmp
	tmp=$(mktemp)
	awk -v mopen="$MARK_OPEN" -v mclose="$MARK_CLOSE" '
		$0 == mopen { skip = 1; next }
		$0 == mclose { skip = 0; next }
		!skip' "$1" >"$tmp" && mv "$tmp" "$1"
}

rc_file() {
	case ${SHELL##*/} in
	zsh) echo "$HOME/.zshrc" ;;
	*) echo "$HOME/.bashrc" ;;
	esac
}

if ((uninstall)); then
	confirm "Remove prompt-watch binaries and config blocks?" || exit 1
	rm -f "$BIN" "$BIN_DIR/prompt-watch-visual"
	strip_block "$TMUX_CONF"
	strip_block "$(rc_file)"
	tmux source-file "$TMUX_CONF" 2>/dev/null || true
	if ((purge)); then
		state="${XDG_STATE_HOME:-$HOME/.local/state}/prompt-watch"
		confirm "Delete all stored drafts in $state?" && rm -rf "$state"
	fi
	echo "prompt-watch removed."
	exit 0
fi

# --- binary ------------------------------------------------------------------

mkdir -p "$BIN_DIR"
src="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/bin/prompt-watch"
if [[ -r $src ]]; then
	cp "$src" "$BIN"
else
	echo "Downloading prompt-watch..."
	curl -fsSL "$REPO_RAW/bin/prompt-watch" -o "$BIN"
fi
chmod +x "$BIN"
ln -sf "$BIN" "$BIN_DIR/prompt-watch-visual"
echo "Installed $BIN"

case :$PATH: in
*:"$BIN_DIR":*) ;;
*) echo "WARNING: $BIN_DIR is not in PATH - add it to your shell rc." ;;
esac

# --- tmux --------------------------------------------------------------------

if confirm "Add the $key picker binding and daemon autostart hook to $TMUX_CONF?"; then
	if [[ -f $TMUX_CONF ]] && grep -v "$MARK_OPEN" "$TMUX_CONF" 2>/dev/null |
		grep -q 'set-hook.*session-created'; then
		echo "WARNING: $TMUX_CONF already sets a session-created hook outside"
		echo "         the prompt-watch block; tmux keeps only one. Merge by hand."
	fi
	strip_block "$TMUX_CONF"
	{
		echo "$MARK_OPEN"
		echo "bind -n $key display-popup -E -w 80% -h 13 -T ' prompt-watch ' \"$BIN __popup 10 '#{pane_id}'\""
		echo "set-hook -g session-created 'run-shell -b \"$BIN ensure\"'"
		echo "$MARK_CLOSE"
	} >>"$TMUX_CONF"
	tmux source-file "$TMUX_CONF" 2>/dev/null || true
	echo "tmux: $key opens the picker; the daemon starts with every new session."
fi

# --- optional Ctrl+G exact copy ---------------------------------------------

if ((ctrl_g)); then
	rc=$(rc_file)
	if confirm "Alias claude so Ctrl+G copies the exact prompt (writes to $rc)?"; then
		strip_block "$rc"
		{
			echo "$MARK_OPEN"
			echo "alias claude='VISUAL=prompt-watch-visual claude'"
			echo "$MARK_CLOSE"
		} >>"$rc"
		echo "Ctrl+G alias written - open a new shell to pick it up."
	fi
fi

"$BIN" ensure || true
sleep 1 # give the detached daemon a beat before doctor checks its pidfile
echo
"$BIN" doctor || true
