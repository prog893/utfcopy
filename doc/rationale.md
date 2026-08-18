# Rationale

Why the tool behaves the way it does, and what was traded away for it.

## The locale is never consulted

Input is decoded as strict UTF-8 and handed to `NSPasteboard` as a `String`, which stores
UTF-16 internally. Nothing reads `LANG`, `LC_ALL` or `LC_CTYPE`.

*Cost:* input that is genuinely in another encoding no longer works by accident. Someone
piping Shift-JIS bytes with `LC_CTYPE=ja_JP.SJIS` set gets an error where `pbcopy` would have
transcoded correctly. That is a real regression for a narrow case, accepted because the
locale-driven path is wrong far more often than it is right, and because `iconv` handles the
narrow case explicitly.

## Invalid UTF-8 is refused, not repaired

`decode` exits 1 and leaves the clipboard untouched. It never substitutes U+FFFD.

The alternative was tempting: salvage what is decodable, warn on stderr, exit 0. That keeps the
`pbcopy` contract that a copy always succeeds. It lost on two counts. The warning disappears
whenever stderr is redirected, which is most of the time in the launch-agent and CI cases this
tool exists for, and a clipboard full of U+FFFD is the same class of silent corruption as the
mojibake being fixed.

*Cost:* not a drop-in for this input. A script piping mixed-encoding data through `pbcopy`
kept working; through `utfcopy` it stops.

## UTF-16 is only decoded behind a BOM

`String(data:encoding:.utf16)` accepts any even-length byte sequence. Feeding it the invalid
UTF-8 `C3 28 41 42` yields `쌨䅂`, a plausible-looking CJK string, with no error.

An unguarded UTF-16 fallback is therefore worse than none: it converts a clean failure into
silent corruption that looks like real text. The BOM requirement means UTF-16 is decoded only
when the input says it is UTF-16.

An odd trailing byte after a BOM is rejected as truncated, because the system decoder discards
it and returns success. `FF FE 41` would otherwise copy an empty string and exit 0.

## Two binaries, with the mode compiled in

`utfcopy` and `utfpaste` are separate executables built from the same source file. The paste
build gets `-D PASTE_MODE`, which selects the mode at compile time, so each binary contains
only its own code path.

An earlier version shipped one binary plus a symlink and read the mode from `argv[0]`, which
is what `pbcopy` does: reached through a symlink named `pbpaste`, the `pbcopy` binary pastes.
That was dropped anyway, because a binary whose behaviour changes when you rename it is
surprising, and it makes `utfpaste` look like an alias rather than a command.

There are also deliberately no `copy` / `paste` subcommands, though an earlier version had
those too. `utfpaste copy` parsed as a copy and cleared the clipboard; a paste invocation
should not be able to destroy the clipboard, and no spelling of the subcommands avoided that
while keeping them.

*Cost:* two compiles instead of one, and SwiftPM needs a second target, which means
`Sources/utfpaste/main.swift` is a git symlink to the real source because SwiftPM refuses to
let two targets share a directory. `utfcopy paste` also no longer works, so anyone who liked
the single-command form uses both names.

## Unknown options are an error

`pbcopy --typo` exits 0 and copies anyway; it ignores everything it does not recognise. Here
an unrecognised flag exits 1.

*Cost:* a script that has been passing a misspelled or since-removed flag to `pbcopy` will
break on switching. The alternative is a flag that quietly does nothing, which is worse.

## -t writes only the named flavour

When `pbcopy` stores RTF it declares four plain-text flavours and fills none of them.
`pbpaste` finds `public.utf8-plain-text` present, reads nil, and prints nothing, so `pbcopy`'s
own RTF is unreachable through `pbpaste`. `make inspect` shows this directly.

`-t rtf` declares only `public.rtf`, leaving no empty promise, which is why plain `pbpaste`
can read what `utfcopy` writes.

*Cost:* a plain-text-only target pastes nothing from `-t html` or `-t rtf`. Copy twice if you
need both flavours present.

## Flavour sniffing matches the pbcopy binary

With no `-t`, a payload starting with `{\rtf` or `%!PS-Adobe-2.0 EPSF-` is stored as that
flavour. Those two literals appear in `/usr/bin/pbcopy` itself, so this follows upstream
rather than guessing at documented behaviour.

## Raw file descriptor I/O on the write path

`utfpaste` uses `write(2)`, not `print()`, and adds no trailing newline, so `$(utfpaste)`
round-trips exactly as with `pbpaste`.

`SIGPIPE` behaviour was measured, not assumed. `utfpaste | head` exits 141, matching
`pbpaste`. An uncaught Objective-C exception would have aborted at 134 instead.

## One source file

A few hundred lines, AppKit only, no dependencies, compiles with a bare `swiftc` call. The
`Package.swift` manifest is there only so Homebrew can build from a git tag.

*Cost:* no unit tests at the function level. Everything is verified end to end through the
real system clipboard instead, which catches integration bugs a unit test would miss and
misses nothing that matters here.

## Notifications, --trim and --wait were removed

An earlier version had `--notify`, `--trim`, `--wait` and `--timeout`, and accepted a file
argument. All were cut to keep the surface identical to `pbcopy` and `pbpaste`.

`--notify` is also impossible to do properly here: an unbundled CLI binary has no bundle
identifier, and `UNUserNotificationCenter.current()` raises
`bundleProxyForCurrentProcess is nil` and terminates the process. Routing through `osascript`
works but shells out to another binary for a cosmetic feature.

The removed flags now exit 1. A script written against the earlier version fails visibly
instead of quietly doing something different.
