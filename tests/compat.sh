#!/usr/bin/env bash
# Portability suite: runs the script under whichever bash invokes this file,
# so it proves bash 3.2 (macOS, and the bash:3.2 image) as well as modern bash.
# Needs no tmux, which keeps it usable in CI containers.
#
#   bash tests/compat.sh          current bash
#   /bin/bash tests/compat.sh     macOS system bash 3.2

set -u

here=$(cd "$(dirname "$0")" && pwd)
PW="$here/../bin/prompt-watch"
FIX="$here/fixtures"
SH=${BASH:-bash}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PW_DIR="$tmp/drafts"
mkdir -p "$PW_DIR"

pass=0 fail=0
check() { # check <name> <expected> <actual>
	if [[ $2 == "$3" ]]; then
		echo "ok    $1"
		pass=$((pass + 1))
	else
		echo "FAIL  $1"
		echo "        expected: $2"
		echo "        actual:   $3"
		fail=$((fail + 1))
	fi
}

echo "bash $BASH_VERSION"
echo

if "$SH" -n "$PW"; then check "syntax parses" ok ok; else check "syntax parses" ok broken; fi

check "version" "prompt-watch 0.1.0" "$("$SH" "$PW" version)"

check "claude one-line" \
	"this is a stored one-line claude draft for the parser fixture" \
	"$("$SH" "$PW" __parse claude <"$FIX/claude-oneline.txt")"

check "claude multi-line keeps lines" "3" \
	"$("$SH" "$PW" __parse claude <"$FIX/claude-multiline.txt" | grep -c '^')"

"$SH" "$PW" __parse claude <"$FIX/claude-empty.txt" >/dev/null 2>&1
check "claude empty box rejected" 1 $?

"$SH" "$PW" __parse claude <"$FIX/claude-placeholder.txt" >/dev/null 2>&1
check "claude placeholder rejected" 1 $?

check "codex one-line" "short codex draft line for fixture" \
	"$("$SH" "$PW" __parse codex <"$FIX/codex-oneline.txt")"

"$SH" "$PW" __parse codex <"$FIX/codex-empty.txt" >/dev/null 2>&1
check "codex empty composer rejected" 1 $?

# adopt: a continuation finds the stored entry
printf 'a draft that keeps growing here\n' >"$PW_DIR/f1.txt"
check "adopt continuation" "$PW_DIR/f1.txt" \
	"$("$SH" "$PW" __adopt "a draft that keeps growing here and more")"

# prune: retention keeps the newest N
export PW_KEEP=3
for i in 1 2 3 4 5; do
	printf 'draft number %s with enough length\n' "$i" >"$PW_DIR/p$i.txt"
	touch "$PW_DIR/p$i.txt"
	sleep 0.05
done
rm -f "$PW_DIR/f1.txt"
"$SH" "$PW" __prune
# shellcheck disable=SC2012 # self-generated names, no spaces or newlines
check "prune keeps PW_KEEP" 3 "$(ls -1 "$PW_DIR"/*.txt | wc -l | tr -d ' ')"
unset PW_KEEP

# doctor runs and reports the bash version; without tmux it must still not crash
out=$("$SH" "$PW" doctor 2>&1)
case $out in
*"bash $BASH_VERSION"*) check "doctor reports this bash" ok ok ;;
*) check "doctor reports this bash" ok "$out" ;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
