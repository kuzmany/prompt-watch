#!/usr/bin/env bats
# Installer regressions. Every test uses an isolated HOME and fake tmux/curl.
# shellcheck disable=SC2016,SC2030,SC2031

setup() {
	ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
	INSTALL="$ROOT/install.sh"
	export HOME="$BATS_TEST_TMPDIR/home"
	export SHELL=/bin/bash
	export PW_INTERVAL=0
	mkdir -p "$HOME" "$BATS_TEST_TMPDIR/fakebin"

	cat >"$BATS_TEST_TMPDIR/fakebin/tmux" <<'EOF'
#!/usr/bin/env bash
case ${1-} in
list-sessions) exit "${PW_TEST_TMUX_STATUS:-1}" ;;
*) exit 0 ;;
esac
EOF
	cat >"$BATS_TEST_TMPDIR/fakebin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while (($#)); do
	case $1 in -o) out=$2; shift ;; esac
	shift
done
[[ -n $out && -s ${PW_TEST_DOWNLOAD:-} ]] || exit 1
cp "$PW_TEST_DOWNLOAD" "$out"
EOF
	chmod +x "$BATS_TEST_TMPDIR/fakebin/tmux" "$BATS_TEST_TMPDIR/fakebin/curl"
	export PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
}

teardown() {
	if [[ -n ${DAEMON_PID:-} ]]; then
		kill "$DAEMON_PID" 2>/dev/null || true
	fi
}

@test "piped install without --yes fails before changing HOME" {
	run bash -c 'cat "$1" | bash' _ "$INSTALL"

	[ "$status" -eq 2 ]
	[[ $output == *"rerun with --yes"* ]]
	[ ! -e "$HOME/.local/bin/prompt-watch" ]
}

@test "install fails before changing HOME when tmux is missing" {
	mkdir -p "$BATS_TEST_TMPDIR/empty-path"

	run env PATH="$BATS_TEST_TMPDIR/empty-path" /usr/bin/bash "$INSTALL" --yes

	[ "$status" -eq 1 ]
	[[ $output == *"tmux is required"* ]]
	[ ! -e "$HOME/.local/bin/prompt-watch" ]
}

@test "piped install downloads source instead of trusting cwd" {
	mkdir -p "$BATS_TEST_TMPDIR/cwd/bin"
	printf '#!/usr/bin/env bash\necho COLLISION\n' >"$BATS_TEST_TMPDIR/cwd/bin/prompt-watch"
	chmod +x "$BATS_TEST_TMPDIR/cwd/bin/prompt-watch"
	export PW_TEST_DOWNLOAD="$ROOT/bin/prompt-watch"

	cd "$BATS_TEST_TMPDIR/cwd"
	run bash -c 'cat "$1" | bash -s -- --yes' _ "$INSTALL"

	[ "$status" -eq 0 ]
	[ -s "$HOME/.local/bin/prompt-watch" ]
	cmp -s "$HOME/.local/bin/prompt-watch" "$ROOT/bin/prompt-watch"
	! cmp -s "$HOME/.local/bin/prompt-watch" "$BATS_TEST_TMPDIR/cwd/bin/prompt-watch"
	grep -qF '# >>> prompt-watch >>>' "$HOME/.tmux.conf"
	grep -Fxq "run-shell -b \"$HOME/.local/bin/prompt-watch ensure\"" "$HOME/.tmux.conf"
}

@test "upgrade repairs state permissions without a running tmux server" {
	mkdir -p "$HOME/.local/state/prompt-watch"
	printf 'private draft\n' >"$HOME/.local/state/prompt-watch/20260902-120000-p7.txt"
	chmod 755 "$HOME/.local/state/prompt-watch"
	chmod 644 "$HOME/.local/state/prompt-watch/20260902-120000-p7.txt"
	export PW_TEST_DOWNLOAD="$ROOT/bin/prompt-watch"

	run bash -c 'cat "$1" | bash -s -- --yes' _ "$INSTALL"

	[ "$status" -eq 0 ]
	[ "$(stat -c %a "$HOME/.local/state/prompt-watch")" = 700 ]
	[ "$(stat -c %a "$HOME/.local/state/prompt-watch/20260902-120000-p7.txt")" = 600 ]
}

@test "installer returns failure when doctor fails" {
	cat >"$BATS_TEST_TMPDIR/failing-prompt-watch" <<'EOF'
#!/usr/bin/env bash
case ${1-} in
ensure) exit 0 ;;
doctor) echo "FAIL  test doctor failure"; exit 1 ;;
esac
EOF
	chmod +x "$BATS_TEST_TMPDIR/failing-prompt-watch"
	export PW_TEST_DOWNLOAD="$BATS_TEST_TMPDIR/failing-prompt-watch"
	export PW_TEST_TMUX_STATUS=0

	run bash -c 'cat "$1" | bash -s -- --yes' _ "$INSTALL"

	[ "$status" -eq 1 ]
	[[ $output == *"FAIL  test doctor failure"* ]]
}

@test "uninstall stops daemon before removing binary" {
	mkdir -p "$HOME/.local/bin" "$HOME/.local/state/prompt-watch"
	cat >"$HOME/.local/bin/prompt-watch" <<'EOF'
#!/usr/bin/env bash
if [[ ${1-} == daemon ]]; then
	echo $$ >"$HOME/.local/state/prompt-watch/.daemon.pid"
	trap 'rm -f "$HOME/.local/state/prompt-watch/.daemon.pid"' EXIT
	while :; do sleep 1; done
fi
EOF
	chmod +x "$HOME/.local/bin/prompt-watch"
	ln -s "$HOME/.local/bin/prompt-watch" "$HOME/.local/bin/prompt-watch-visual"
	(setsid "$HOME/.local/bin/prompt-watch" daemon >/dev/null 2>&1 &)
	for _ in 1 2 3 4 5; do
		[[ -r $HOME/.local/state/prompt-watch/.daemon.pid ]] && break
		sleep 1
	done
	[ -s "$HOME/.local/state/prompt-watch/.daemon.pid" ]
	DAEMON_PID=$(<"$HOME/.local/state/prompt-watch/.daemon.pid")
	kill -0 "$DAEMON_PID"

	run bash "$INSTALL" --uninstall --yes

	[ "$status" -eq 0 ]
	! kill -0 "$DAEMON_PID" 2>/dev/null
	[ ! -e "$HOME/.local/bin/prompt-watch" ]
	[ ! -e "$HOME/.local/bin/prompt-watch-visual" ]
	DAEMON_PID=""
}

@test "malformed marker aborts without changing dotfile" {
	cat >"$HOME/.tmux.conf" <<'EOF'
keep-before
# >>> prompt-watch >>>
keep-after-unclosed-marker
EOF
	cp "$HOME/.tmux.conf" "$BATS_TEST_TMPDIR/original.conf"
	[ -s "$BATS_TEST_TMPDIR/original.conf" ]

	run bash "$INSTALL" --uninstall --yes

	[ "$status" -ne 0 ]
	[[ $output == *"malformed prompt-watch marker block"* ]]
	cmp -s "$HOME/.tmux.conf" "$BATS_TEST_TMPDIR/original.conf"
}

@test "purge removes only prompt-watch-owned files" {
	state="$BATS_TEST_TMPDIR/shared-state"
	mkdir -p "$state"
	printf 'draft\n' >"$state/20260902-120000-p7.txt"
	printf 'keep\n' >"$state/notes.txt"
	printf 'keep\n' >"$state/database"
	printf '123\n' >"$state/.daemon.pid"

	run env PW_DIR="$state" bash "$INSTALL" --uninstall --purge --yes

	[ "$status" -eq 0 ]
	[ ! -e "$state/20260902-120000-p7.txt" ]
	[ ! -e "$state/.daemon.pid" ]
	[ -e "$state/notes.txt" ]
	[ -e "$state/database" ]
}
