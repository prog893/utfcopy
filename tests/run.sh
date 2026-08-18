#!/bin/bash
# utfcopy test suite
#
# Differential tests against the system pbcopy/pbpaste. Two classes of assertion:
#
#   1. Parity   - under a healthy UTF-8 locale utfcopy must agree with pbcopy,
#                 so it is a safe drop-in replacement.
#   2. Divergence - under a broken locale chain pbcopy corrupts non-ASCII and
#                 utfcopy must not. These tests fail if the bug we exist to fix
#                 ever stops reproducing, which would mean the tool is obsolete.
#
# The system clipboard is saved on entry and restored on exit.

set -uo pipefail

BUILD="$(cd "$(dirname "$0")/.." && pwd)/build"
COPY="$BUILD/utfcopy"
PASTE="$BUILD/utfpaste"

pass=0; fail=0; failed_names=()

red()   { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m'  "$1"; }

# --- clipboard preservation -------------------------------------------------
SAVED_CLIPBOARD="$(pbpaste 2>/dev/null || true)"
restore_clipboard() {
    printf '%s' "$SAVED_CLIPBOARD" | pbcopy 2>/dev/null || true
    echo
    if [ "$fail" -eq 0 ]; then
        green "All $pass tests passed."; echo
    else
        red "$fail of $((pass + fail)) tests failed:"; echo
        for n in "${failed_names[@]}"; do echo "  - $n"; done
    fi
    [ "$fail" -eq 0 ]
}
trap 'restore_clipboard' EXIT

ok() { pass=$((pass + 1)); printf '  %s %s\n' "$(green '✓')" "$1"; }
no() {
    fail=$((fail + 1)); failed_names+=("$1")
    printf '  %s %s\n' "$(red '✗')" "$1"
    printf '      expected: %s\n' "$(dim "$(printf '%q' "$2")")"
    printf '      actual:   %s\n' "$(dim "$(printf '%q' "$3")")"
}

# assert_eq <name> <expected> <actual>
assert_eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "$2" "$3"; }

section() { echo; printf '%s\n' "$(dim "── $1")"; }

# A locale environment as hostile as a launch agent or `env -i` shell.
broken_env() { env -u LANG -u LC_ALL -u LC_CTYPE LC_ALL=C "$@"; }

if [ ! -x "$COPY" ]; then
    red "build first: make build"; echo; exit 1
fi

UNI='Hello ✅ 日本語 🎉'

# ---------------------------------------------------------------------------
section "round trip fidelity"

for label_payload in \
    "ascii:hello world" \
    "emoji:✅ 🎉 🚀" \
    "cjk:日本語のテキスト" \
    "mixed:$UNI" \
    "combining:é vs é" \
    "zwj family:👨‍👩‍👧‍👦" \
    "flag:🇯🇵" \
    "skin tone:👍🏽" \
    "rtl:مرحبا بالعالم" \
    "cyrillic:Привет мир" \
    "math:∑ ∫ √ ≠ ∞" \
    "quotes:“curly” ‘quotes’" \
    "emdash:a — b – c" \
    "astral plane:𠜎𠜱𡿺" \
    "variation selector:☺️ vs ☺" \
    "zalgo:Z̸̧̢a̸̧l̸g̸o̸" \
    "box drawing:┌───┬───┐│ a │ b │└───┴───┘" \
    "korean:한국어 텍스트" \
    "control bytes:$(printf 'a\x01b\x7fc')" \
    ; do
    label="${label_payload%%:*}"; payload="${label_payload#*:}"
    printf '%s' "$payload" | "$COPY"
    assert_eq "round trip: $label" "$payload" "$("$PASTE")"
done

# ---------------------------------------------------------------------------
section "byte exactness"

# No trailing newline invented, matching pbpaste.
printf 'no-newline' | "$COPY"
assert_eq "no trailing newline added" "10" "$("$PASTE" | wc -c | tr -d ' ')"

# Tabs and multiple spaces survive.
printf 'tab\tsep\t✅\tvals' | "$COPY"
assert_eq "tabs preserved" "tab	sep	✅	vals" "$("$PASTE")"

# Interior and trailing newlines are kept verbatim.
printf 'line1\nline2\n' | "$COPY"
assert_eq "trailing newline kept" "$(printf 'line1\nline2\n' | xxd -p)" "$("$PASTE" | xxd -p)"

# NUL is not valid in an NSString-backed pasteboard; assert we do not crash.
printf 'a\0b' | "$COPY" 2>/dev/null
assert_eq "NUL byte does not crash (exit 0)" "0" "$?"

# Large payload, well past the 64k read buffer.
python3 -c "print('✅日本語' * 20000, end='')" | "$COPY"
assert_eq "240KB payload intact" "240000" "$("$PASTE" | wc -c | tr -d ' ')"

# Empty input is a legal copy.
printf '' | "$COPY"
assert_eq "empty input exits 0" "0" "$?"
assert_eq "empty input yields empty paste" "" "$("$PASTE")"

# ---------------------------------------------------------------------------
section "parity with pbcopy under a healthy UTF-8 locale"

# The drop-in guarantee: same input, same pasteboard contents.
for payload in "$UNI" "plain ascii" "👨‍👩‍👧‍👦 family" "Привет"; do
    printf '%s' "$payload" | LANG=en_US.UTF-8 pbcopy
    via_pb="$(LANG=en_US.UTF-8 pbpaste)"
    printf '%s' "$payload" | "$COPY"
    via_utf="$("$PASTE")"
    assert_eq "pbcopy parity: ${payload:0:16}" "$via_pb" "$via_utf"
done

# Our paste must read a pbcopy-written clipboard, and vice versa.
printf '%s' "$UNI" | LANG=en_US.UTF-8 pbcopy
assert_eq "utfpaste reads pbcopy's clipboard" "$UNI" "$("$PASTE")"
printf '%s' "$UNI" | "$COPY"
assert_eq "pbpaste reads utfcopy's clipboard" "$UNI" "$(LANG=en_US.UTF-8 pbpaste)"

# ---------------------------------------------------------------------------
section "divergence from pbcopy under a broken locale"

# This is the bug the tool exists to fix. pbcopy stores MacRoman-interpreted
# bytes, so a UTF-8 reader sees mojibake. If these ever start passing for
# pbcopy, the tool is no longer needed.
printf '%s' "$UNI" | broken_env pbcopy
pb_broken="$(LANG=en_US.UTF-8 pbpaste)"
if [ "$pb_broken" != "$UNI" ]; then
    ok "pbcopy corrupts unicode under LC_ALL=C (bug reproduces)"
else
    no "pbcopy corrupts unicode under LC_ALL=C (bug reproduces)" "mojibake" "$pb_broken"
fi

printf '%s' "$UNI" | broken_env "$COPY"
assert_eq "utfcopy is correct under LC_ALL=C" "$UNI" "$(LANG=en_US.UTF-8 pbpaste)"

# The harshest case: no environment at all.
printf '%s' "$UNI" | env -i "$COPY"
assert_eq "utfcopy is correct under env -i" "$UNI" "$(LANG=en_US.UTF-8 pbpaste)"

printf '%s' "$UNI" | "$COPY"
assert_eq "utfpaste is correct under env -i" "$UNI" "$(env -i "$PASTE")"

# A locale claiming a single-byte encoding must not affect us either.
printf '%s' "$UNI" | env LC_ALL=en_US.ISO8859-1 "$COPY"
assert_eq "utfcopy ignores an ISO8859-1 locale" "$UNI" "$(LANG=en_US.UTF-8 pbpaste)"

# ---------------------------------------------------------------------------
section "two independent binaries"

printf 'dispatch check ✅' | "$COPY"
assert_eq "utfcopy writes, utfpaste reads" "dispatch check ✅" "$("$PASTE")"

# They are separate executables, not one binary linked twice, so neither can be
# turned into the other.
if [ -L "$COPY" ] || [ -L "$PASTE" ]; then
    no "neither binary is a symlink" "two regular files" "at least one symlink"
else
    ok "neither binary is a symlink"
fi
if [ "$(shasum -a 256 <"$COPY")" = "$(shasum -a 256 <"$PASTE")" ]; then
    no "binaries differ" "different builds" "identical bytes"
else
    ok "binaries differ"
fi

# Mode is compiled in, so a renamed copy of utfcopy still copies. Under the old
# argv[0] scheme this pasted instead, which meant renaming a binary silently
# changed what it did.
renamed="$(mktemp -t utfpaste-impostor)" && rm -f "$renamed"
cp "$COPY" "$renamed"
printf 'sentinel' | "$COPY"
printf 'via renamed binary ✅' | "$renamed"
assert_eq "renaming utfcopy does not make it paste" "via renamed binary ✅" "$("$PASTE")"
rm -f "$renamed"

# -Prefer is a pbpaste flag, so the copy side rejects it instead of accepting a
# flag that would do nothing.
printf 'x' | "$COPY" -Prefer txt >/dev/null 2>&1
assert_eq "utfcopy rejects -Prefer" "1" "$?"

# There are no copy/paste subcommands. `utfpaste copy` must not be a way to clear
# the clipboard, so the word is rejected as an unknown option instead.
printf 'sentinel' | "$COPY"
"$PASTE" copy </dev/null >/dev/null 2>&1
assert_eq "'utfpaste copy' is rejected" "1" "$?"
assert_eq "rejected subcommand leaves clipboard intact" "sentinel" "$("$PASTE")"

"$COPY" copy </dev/null >/dev/null 2>&1
assert_eq "'utfcopy copy' is rejected" "1" "$?"

# Scope matches pbcopy: no file argument, so stdin is the only input. A stray
# argument is an error rather than a silently ignored filename.
"$COPY" /etc/hosts </dev/null >/dev/null 2>&1
assert_eq "file argument is rejected" "1" "$?"

# ---------------------------------------------------------------------------
section "flags"

printf '<b>bold ✅</b>' | "$COPY" -t html
assert_eq "-t html round trip" "<b>bold ✅</b>" "$("$PASTE" -t html)"
assert_eq "html write does not populate plain text" "" "$("$PASTE")"

printf '<i>x</i>' | "$COPY" --type html
assert_eq "--type long form" "<i>x</i>" "$("$PASTE" --type html)"

printf 'find board ✅' | "$COPY" -pboard find
assert_eq "-pboard find is isolated from general" "find board ✅" "$("$PASTE" -pboard find)"

printf 'general board' | "$COPY"
printf 'other board' | "$COPY" -pboard find
assert_eq "-pboard general unaffected by find write" "general board" "$("$PASTE")"

printf 'prefer txt ✅' | "$COPY"
assert_eq "-Prefer txt" "prefer txt ✅" "$("$PASTE" -Prefer txt)"
assert_eq "-Prefer rtf falls back to text" "prefer txt ✅" "$("$PASTE" -Prefer rtf)"

# ---------------------------------------------------------------------------
section "exit codes and errors"

printf 'x' | "$COPY" >/dev/null 2>&1
assert_eq "copy success exits 0" "0" "$?"

"$PASTE" >/dev/null 2>&1
assert_eq "paste success exits 0" "0" "$?"

"$COPY" /nonexistent/path/xyz </dev/null 2>/dev/null
assert_eq "unreadable file exits 1" "1" "$?"

printf 'x' | "$COPY" --nonsense-flag >/dev/null 2>&1
assert_eq "unknown flag exits 1" "1" "$?"

printf 'x' | "$COPY" -t bogus >/dev/null 2>&1
assert_eq "invalid --type exits 1" "1" "$?"

printf 'x' | "$COPY" -pboard bogus >/dev/null 2>&1
assert_eq "invalid -pboard exits 1" "1" "$?"

printf 'x' | "$COPY" -t >/dev/null 2>&1
assert_eq "missing flag value exits 1" "1" "$?"

"$COPY" --help >/dev/null 2>&1
assert_eq "--help exits 0" "0" "$?"

"$COPY" -help >/dev/null 2>&1
assert_eq "-help (pbcopy form) exits 0" "0" "$?"

"$COPY" --version >/dev/null 2>&1
assert_eq "--version exits 0" "0" "$?"

assert_eq "--version prints a version" "utfcopy" "$("$COPY" --version | cut -d' ' -f1)"

# Invalid UTF-8 is refused outright rather than salvaged with U+FFFD. A lossy
# decode is the corruption this tool exists to prevent, and it would be silent
# whenever stderr is discarded, so it is an error instead.
for bad in '\xc3\x28' '\xe2\x9c' '\x80\x80' '\xf8\xa1\xa1\xa1' 'bad \xff bytes'; do
    printf "$bad" | "$COPY" >/dev/null 2>&1
    assert_eq "invalid UTF-8 ($bad) exits 1" "1" "$?"
done

warn_out="$(printf 'bad \xff bytes' | "$COPY" 2>&1 >/dev/null)"
case "$warn_out" in
    *"not valid UTF-8"*) ok "invalid UTF-8 explains itself on stderr" ;;
    *) no "invalid UTF-8 explains itself on stderr" "a message" "$warn_out" ;;
esac

# A refused copy must not disturb what was already on the clipboard.
printf 'sentinel value' | "$COPY"
printf '\xc3\x28' | "$COPY" >/dev/null 2>&1
assert_eq "refused copy leaves clipboard intact" "sentinel value" "$("$PASTE")"

# A UTF-16 BOM followed by an odd byte count is truncated input. The system
# decoder drops the dangling byte silently, so we reject it instead.
printf '\xff\xfe\x41' | "$COPY" >/dev/null 2>&1
assert_eq "odd-length UTF-16 exits 1" "1" "$?"

# A UTF-16 BOM is honoured, but BOM-less invalid bytes must not be misread as
# UTF-16 (String(data:encoding:.utf16) accepts any even-length input).
python3 -c "import sys; sys.stdout.buffer.write('utf16 ✅'.encode('utf-16'))" | "$COPY" 2>/dev/null
assert_eq "UTF-16 BOM input decoded correctly" "utf16 ✅" "$("$PASTE")"

# SIGPIPE must kill us the same way it kills pbpaste (141), not abort (134) via
# an uncaught ObjC exception from FileHandle.
python3 -c "print('line ✅ ' * 50000)" | "$COPY"
"$PASTE" 2>/dev/null | head -c 10 >/dev/null
utf_pipe=$?
pbpaste 2>/dev/null | head -c 10 >/dev/null
pb_pipe=$?
assert_eq "SIGPIPE status matches pbpaste" "$pb_pipe" "$utf_pipe"
case "$utf_pipe" in
    134) no "SIGPIPE is not an ObjC abort" "not 134" "134 (SIGABRT)" ;;
    *)   ok "SIGPIPE is not an ObjC abort" ;;
esac

# ---------------------------------------------------------------------------
section "scope: flags we do not have"

# The removed conveniences must be rejected, not silently accepted, so a script
# written against an older build fails loudly instead of behaving differently.
for gone in --trim --notify --wait "--timeout 1"; do
    printf 'x' | "$COPY" $gone >/dev/null 2>&1
    assert_eq "removed flag $gone exits 1" "1" "$?"
done

# ---------------------------------------------------------------------------
section "-t recovers what pbpaste loses"

# Case 1: pbcopy writing RTF itself. It declares four plain-text flavours and
# fills none of them, so pbpaste finds public.utf8-plain-text present, reads nil,
# and prints nothing. The RTF is unreachable through pbpaste even with
# -Prefer rtf. Run `make inspect` to see the declared-but-empty types directly.
printf '{\\rtf1\\ansi via pbcopy}' | pbcopy
lost="$(pbpaste)"
lost_pref="$(pbpaste -Prefer rtf)"
recovered="$("$PASTE" -t rtf)"
if [ -z "$lost" ] && [ -z "$lost_pref" ]; then
    ok "pbpaste cannot reach pbcopy's own rtf"
else
    no "pbpaste cannot reach pbcopy's own rtf" "empty" "$lost / $lost_pref"
fi
assert_eq "-t rtf recovers it" '{\rtf1\ansi via pbcopy}' "$recovered"

# Case 2: RTF written the way a real editor writes it, as an NSAttributedString
# through writeObjects. Here the plain-text flavour IS filled, so nothing is lost
# and every reader agrees on the text. This is the common case, and it is why the
# empty-promise bug above is specific to pbcopy rather than to RTF in general.
if [ -x "$BUILD/pbinspect" ]; then
    "$BUILD/pbinspect" --write-rtf >/dev/null
    assert_eq "app-style rtf: plain text is present" "bold unicode ✅ 日本語" "$(pbpaste)"
    assert_eq "app-style rtf: utfpaste agrees" "bold unicode ✅ 日本語" "$("$PASTE")"

    # -t rtf must return the markup, not the plain text.
    rtf_out="$("$PASTE" -t rtf)"
    case "$rtf_out" in
        '{\rtf1'*) ok "-t rtf returns rtf markup, not plain text" ;;
        *) no "-t rtf returns rtf markup, not plain text" '{\rtf1...' "$(printf '%s' "$rtf_out" | head -c 40)" ;;
    esac

    # -Prefer is inert: pbpaste returns the same bytes whatever you ask for, even
    # when the rtf flavour is present and readable. -t is the only thing that
    # actually selects a flavour.
    pref_rtf="$(pbpaste -Prefer rtf | md5)"
    pref_txt="$(pbpaste -Prefer txt | md5)"
    ours_rtf="$("$PASTE" -t rtf | md5)"
    if [ "$pref_rtf" = "$pref_txt" ] && [ "$ours_rtf" != "$pref_rtf" ]; then
        ok "-Prefer rtf is inert; -t rtf is not"
    else
        no "-Prefer rtf is inert; -t rtf is not" "prefer rtf == prefer txt != -t rtf" \
           "$pref_rtf / $pref_txt / $ours_rtf"
    fi
else
    printf '  %s app-style rtf checks (build/pbinspect not built)\n' "$(dim 'skip')"
fi

# Our own -t rtf declares only public.rtf, so it leaves no empty promise behind
# and even plain pbpaste can fall back to it.
printf '{\\rtf1\\ansi via utfcopy}' | "$COPY" -t rtf
assert_eq "-t rtf round trip" '{\rtf1\ansi via utfcopy}' "$("$PASTE" -t rtf)"
assert_eq "pbpaste can read our rtf" '{\rtf1\ansi via utfcopy}' "$(pbpaste)"

# Asking for a flavour that is absent is empty output and still exit 0, matching
# pbpaste when it finds nothing.
printf 'plain only' | "$COPY" -t string
assert_eq "absent flavour yields empty output" "" "$("$PASTE" -t html)"
"$PASTE" -t html >/dev/null 2>&1
assert_eq "absent flavour still exits 0" "0" "$?"

# ---------------------------------------------------------------------------
section "BOM handling"

# A UTF-8 BOM is consumed rather than copied through as U+FEFF.
printf '\xef\xbb\xbfbom stripped ✅' | "$COPY"
assert_eq "UTF-8 BOM is stripped" "bom stripped ✅" "$("$PASTE")"

# UTF-16LE and BE, which pbcopy cannot read at all.
python3 -c "import sys; sys.stdout.buffer.write('le ✅ 日本語'.encode('utf-16-le'))" \
    | { printf '\xff\xfe'; cat; } | "$COPY"
assert_eq "UTF-16LE BOM decoded" "le ✅ 日本語" "$("$PASTE")"

python3 -c "import sys; sys.stdout.buffer.write('be ✅ 日本語'.encode('utf-16-be'))" \
    | { printf '\xfe\xff'; cat; } | "$COPY"
assert_eq "UTF-16BE BOM decoded" "be ✅ 日本語" "$("$PASTE")"

exit 0
