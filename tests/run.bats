#!/usr/bin/env bats
# Parser, adopt and prune tests - no tmux needed, safe for CI.

setup() {
	PW="$BATS_TEST_DIRNAME/../bin/prompt-watch"
	FIX="$BATS_TEST_DIRNAME/fixtures"
	export PW_DIR="$BATS_TEST_TMPDIR/drafts"
	mkdir -p "$PW_DIR"
}

teardown() {
	[[ -z ${OTHER_PID:-} ]] || kill "$OTHER_PID" 2>/dev/null || true
}

# --- claude parser -----------------------------------------------------------

@test "claude: one-line draft extracted exactly" {
	run "$PW" __parse claude <"$FIX/claude-oneline.txt"
	[ "$status" -eq 0 ]
	[ "$output" = "this is a stored one-line claude draft for the parser fixture" ]
}

@test "claude: multi-line draft keeps its lines" {
	run "$PW" __parse claude <"$FIX/claude-multiline.txt"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "first line of a multi-line claude draft that keeps going" ]
	[ "${lines[1]}" = "second line of the draft after a newline" ]
	[ "${lines[2]}" = "third line ends here" ]
}

@test "claude: empty box rejected" {
	run "$PW" __parse claude <"$FIX/claude-empty.txt"
	[ "$status" -ne 0 ]
}

@test "claude: queued-messages hint rejected" {
	run "$PW" __parse claude <"$FIX/claude-hint.txt"
	[ "$status" -ne 0 ]
}

@test "claude: dialog between rules rejected (no marker)" {
	run "$PW" __parse claude <"$FIX/claude-dialog.txt"
	[ "$status" -ne 0 ]
}

# --- codex parser ------------------------------------------------------------

@test "codex: one-line draft extracted exactly" {
	run "$PW" __parse codex <"$FIX/codex-oneline.txt"
	[ "$status" -eq 0 ]
	[ "$output" = "short codex draft line for fixture" ]
}

@test "codex: multi-line draft spans wrap and newline" {
	run "$PW" __parse codex <"$FIX/codex-multiline.txt"
	[ "$status" -eq 0 ]
	[[ ${lines[0]} == "This is a long test draft for the prompt-watch parser"* ]]
	[[ $output == *"second paragraph after a newline" ]]
}

@test "codex: empty composer placeholder rejected" {
	run "$PW" __parse codex <"$FIX/codex-empty.txt"
	[ "$status" -ne 0 ]
}

# --- adopt -------------------------------------------------------------------

@test "adopt: a continuation adopts the stored entry" {
	printf 'a draft that keeps growing here\n' >"$PW_DIR/f1.txt"
	run "$PW" __adopt "a draft that keeps growing here and growing more"
	[ "$status" -eq 0 ]
	[[ $output == *"/f1.txt" ]]
}

@test "adopt: a short stored entry cannot swallow drafts" {
	printf 'a draft th\n' >"$PW_DIR/f1.txt" # under PW_MINLEN
	run "$PW" __adopt "a draft that keeps growing here and growing more"
	[ "$status" -ne 0 ]
}

@test "adopt: an unrelated draft starts a new entry" {
	printf 'a draft that keeps growing here\n' >"$PW_DIR/f1.txt"
	run "$PW" __adopt "something entirely different from the stored one"
	[ "$status" -ne 0 ]
}

# --- prune -------------------------------------------------------------------

@test "prune: keeps only the newest PW_KEEP drafts" {
	export PW_KEEP=5
	for i in 1 2 3 4 5 6 7 8; do
		printf 'draft number %s with enough length\n' "$i" >"$PW_DIR/f$i.txt"
		touch -d "-$((9 - i)) seconds" "$PW_DIR/f$i.txt"
	done
	run "$PW" __prune
	[ "$status" -eq 0 ]
	[ "$(ls -1 "$PW_DIR"/*.txt | wc -l)" -eq 5 ]
	[ -f "$PW_DIR/f8.txt" ] # newest survives
	[ ! -f "$PW_DIR/f1.txt" ] # oldest is gone
}

# --- surface -----------------------------------------------------------------

@test "help lists the public surface only" {
	run "$PW" --help
	[ "$status" -eq 0 ]
	[[ $output == *"prompt-watch"* ]]
	[[ $output == *doctor* ]]
	[[ $output != *"paste N"* ]] # cut from v1
}

@test "version prints" {
	run "$PW" version
	[ "$status" -eq 0 ]
	[[ $output == "prompt-watch "* ]]
}

@test "doctor runs and reports bash" {
	run "$PW" doctor
	[[ $output == *bash* ]]
}

@test "claude: rotating Try \"...\" placeholder rejected" {
	run "$PW" __parse claude <"$FIX/claude-placeholder.txt"
	[ "$status" -ne 0 ]
}

@test "claude: a real draft that starts with Try \"...\" still recovers" {
	run "$PW" __parse claude <"$FIX/claude-try-prefix.txt"
	[ "$status" -eq 0 ]
	[ "$output" = 'Try "refactor" and then rewrite the parser' ]
}

@test "state: existing directory and drafts become private" {
	printf 'private prompt draft\n' >"$PW_DIR/f1.txt"
	chmod 755 "$PW_DIR"
	chmod 644 "$PW_DIR/f1.txt"

	run "$PW" doctor

	[ "$(stat -c %a "$PW_DIR")" = 700 ]
	[ "$(stat -c %a "$PW_DIR/f1.txt")" = 600 ]
}

@test "doctor: unrelated live pid is not a daemon" {
	sleep 60 &
	OTHER_PID=$!
	printf '%s\n' "$OTHER_PID" >"$PW_DIR/.daemon.pid"

	run "$PW" doctor

	[[ $output == *"FAIL  daemon not running"* ]]
}
