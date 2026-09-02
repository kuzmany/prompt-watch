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
umask 077

REPO_RAW="https://raw.githubusercontent.com/kuzmany/prompt-watch/main"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/prompt-watch"
TMUX_CONF="$HOME/.tmux.conf"
STATE_DIR="${PW_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/prompt-watch}"
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

if ((!yes)) && [[ ! -t 0 ]]; then
	echo "ERROR: confirmation needs a terminal; rerun with --yes." >&2
	exit 2
fi

confirm() {
	((yes)) && return 0
	local a
	read -r -p "$1 [y/N] " a
	[[ $a == y || $a == Y ]]
}

validate_block() {
	[[ -f $1 ]] || return 0
	if ! awk -v mopen="$MARK_OPEN" -v mclose="$MARK_CLOSE" '
		$0 == mopen { if (inside) bad = 1; inside = 1; next }
		$0 == mclose { if (!inside) bad = 1; inside = 0; next }
		END { exit (inside || bad) }
	' "$1" >/dev/null; then
		echo "ERROR: malformed prompt-watch marker block in $1; file left unchanged." >&2
		return 1
	fi
}

# Remove our marker block from a file, in place, if present.
strip_block() {
	[[ -f $1 ]] || return 0
	validate_block "$1" || return 1
	grep -qF "$MARK_OPEN" "$1" || return 0
	local tmp
	tmp=$(mktemp "$1.prompt-watch.XXXXXX")
	cp -p "$1" "$tmp"
	if awk -v mopen="$MARK_OPEN" -v mclose="$MARK_CLOSE" '
		$0 == mopen { skip = 1; next }
		$0 == mclose { skip = 0; next }
		!skip' "$1" >"$tmp"; then
		mv "$tmp" "$1"
	else
		rm -f "$tmp"
		return 1
	fi
}

rc_file() {
	case ${SHELL##*/} in
	zsh) echo "$HOME/.zshrc" ;;
	*) echo "$HOME/.bashrc" ;;
	esac
}

running_daemon_pid() {
	local pidfile="$STATE_DIR/.daemon.pid" pid args
	[[ -r $pidfile ]] || return 1
	IFS= read -r pid <"$pidfile" || return 1
	case $pid in '' | *[!0-9]*) return 1 ;; esac
	kill -0 "$pid" 2>/dev/null || return 1
	args=$(ps -ww -p "$pid" -o args= 2>/dev/null) || return 1
	[[ $args == "prompt-watch daemon" || $args == *"/prompt-watch daemon" ]] || return 1
	printf '%s\n' "$pid"
}

stop_daemon() {
	local pidfile="$STATE_DIR/.daemon.pid" pid i=0
	if ! pid=$(running_daemon_pid); then
		rm -f "$pidfile"
		return 0
	fi
	kill "$pid"
	while kill -0 "$pid" 2>/dev/null && ((i < 3)); do
		sleep 1
		((i += 1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		echo "ERROR: prompt-watch daemon $pid did not stop; installation left unchanged." >&2
		return 1
	fi
	rm -f "$pidfile"
}

secure_state() {
	local f
	[[ -d $STATE_DIR ]] || return 0
	chmod 700 "$STATE_DIR"
	for f in "$STATE_DIR"/*.txt "$STATE_DIR/.daemon.pid" "$STATE_DIR/.panemap" "$STATE_DIR/.panemap.tmp"; do
		[[ -e $f ]] || continue
		chmod 600 "$f"
	done
}

purge_state() {
	local f name draft_re='^[0-9]{8}-[0-9]{6}-p[0-9]+\.txt$'
	[[ -d $STATE_DIR ]] || return 0
	for f in "$STATE_DIR"/*.txt; do
		[[ -f $f ]] || continue
		name=${f##*/}
		[[ $name =~ $draft_re ]] && rm -f "$f"
	done
	rm -f "$STATE_DIR/.daemon.pid" "$STATE_DIR/.panemap" "$STATE_DIR/.panemap.tmp"
	if ! rmdir "$STATE_DIR" 2>/dev/null; then
		echo "WARNING: kept unknown files in $STATE_DIR" >&2
	fi
}

if ((uninstall)); then
	confirm "Remove prompt-watch binaries and config blocks?" || exit 1
	validate_block "$TMUX_CONF"
	validate_block "$(rc_file)"
	stop_daemon
	rm -f "$BIN" "$BIN_DIR/prompt-watch-visual"
	strip_block "$TMUX_CONF"
	strip_block "$(rc_file)"
	tmux source-file "$TMUX_CONF" 2>/dev/null || true
	if ((purge)); then
		confirm "Delete all stored drafts in $STATE_DIR?" && purge_state
	fi
	echo "prompt-watch removed."
	exit 0
fi

# --- binary ------------------------------------------------------------------

if ! command -v tmux >/dev/null 2>&1; then
	echo "ERROR: tmux is required; install tmux first." >&2
	exit 1
fi
validate_block "$TMUX_CONF"
((ctrl_g)) && validate_block "$(rc_file)"
mkdir -p "$BIN_DIR"
tmp=$(mktemp "$BIN_DIR/.prompt-watch.XXXXXX")
trap '[[ -z ${tmp:-} ]] || rm -f "$tmp"' EXIT
src=""
script_path=${BASH_SOURCE[0]-}
if [[ -n $script_path && -f $script_path ]]; then
	script_dir=$(cd "$(dirname "$script_path")" 2>/dev/null && pwd)
	[[ -r $script_dir/bin/prompt-watch ]] && src="$script_dir/bin/prompt-watch"
fi
if [[ -n $src ]]; then
	cp "$src" "$tmp"
else
	echo "Downloading prompt-watch..."
	curl -fsSL "$REPO_RAW/bin/prompt-watch" -o "$tmp"
fi
bash -n "$tmp"
chmod +x "$tmp"
stop_daemon
mv "$tmp" "$BIN"
tmp=""
trap - EXIT
secure_state
ln -sf "$BIN" "$BIN_DIR/prompt-watch-visual"
echo "Installed $BIN"

case :$PATH: in
*:"$BIN_DIR":*) ;;
*) echo "WARNING: $BIN_DIR is not in PATH - add it to your shell rc." ;;
esac

# --- tmux --------------------------------------------------------------------

if confirm "Add the $key picker binding and daemon autostart hook to $TMUX_CONF?"; then
	strip_block "$TMUX_CONF"
	if [[ -f $TMUX_CONF ]] && grep -q 'set-hook.*session-created' "$TMUX_CONF"; then
		echo "WARNING: $TMUX_CONF already sets a session-created hook outside"
		echo "         the prompt-watch block; tmux keeps only one. Merge by hand."
	fi
	{
		echo "$MARK_OPEN"
		echo "bind -n $key display-popup -E -w 80% -h 13 -T ' prompt-watch ' \"$BIN __popup 10 '#{pane_id}'\""
		echo "run-shell -b \"$BIN ensure\""
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

if tmux list-sessions >/dev/null 2>&1; then
	"$BIN" ensure
	sleep 1 # give the detached daemon a beat before doctor checks its pidfile
	echo
	if out=$("$BIN" doctor 2>&1); then
		echo "Done. Press $key inside tmux to get a lost prompt back."
	else
		echo "$out"
		echo
		echo "Installed, but something is off - see the FAIL lines above."
		echo "Fix it, then check again with: prompt-watch doctor"
		exit 1
	fi
else
	echo
	echo "Done. Start tmux, then press $key to open prompt-watch."
fi
