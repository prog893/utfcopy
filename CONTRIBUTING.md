# Contributing

## Layout

```
Sources/utfcopy/main.swift    the whole tool
tests/run.sh                  differential suite against pbcopy/pbpaste
scripts/pbinspect.swift       pasteboard inspector, dev only
doc/rationale.md              why each behaviour was chosen, and its cost
doc/release-checklist.md      tagging and the formula bump
Makefile                      build, test, install
```

One source file on purpose. It is a few hundred lines, has no dependencies beyond AppKit,
and compiles with a bare `swiftc` call, so it should stay something you can read in a sitting.

## Build and test

```bash
make build      # both binaries into build/
make test       # runs tests/run.sh
make universal  # arm64 + x86_64 fat binary, for a release
make clean
```

`swift build -c release` also works; the SwiftPM manifest exists so Homebrew can build from
a git tag. It defines two executable targets, so it produces both binaries.
`Sources/utfpaste/main.swift` is a git symlink to the utfcopy source, since SwiftPM will not
let two targets share a directory.

## The test suite

`make test` drives the real system clipboard and compares against the real `pbcopy` and
`pbpaste`. It saves the clipboard on entry and restores it on exit, but it does clobber the
clipboard while running.

Assertions come in two kinds, and the second is the unusual one:

*Parity.* Under a healthy UTF-8 locale, `utfcopy` must agree with `pbcopy` byte for byte, and
each tool must read what the other wrote. This is what makes it a safe drop-in.

*Divergence.* Under `LC_ALL=C`, `LC_ALL=en_US.ISO8859-1` and `env -i`, `pbcopy` must corrupt
non-ASCII input and `utfcopy` must not. These assert that the bug still exists. If the
`pbcopy` half ever starts passing, Apple has fixed the encoding handling and this tool has no
reason to exist, so the suite is designed to tell you that rather than hide it.

Current coverage includes ZWJ sequences, skin tone modifiers, regional indicator flags,
combining marks, RTL text, astral plane characters, zalgo, tab and control byte preservation,
a 240 KB piped payload, BOM handling for UTF-8 and UTF-16 in both endiannesses, truncated and
invalid input, `SIGPIPE` behaviour matching `pbpaste`, both RTF flavour cases, that the two
binaries are genuinely independent, and every exit code.

When adding a behaviour, add the assertion that would have caught its absence. Several
existing checks exist because an earlier version of this tool got them wrong: the UTF-16 BOM
gate, the odd-trailing-byte rejection, and the rejection of `utfpaste copy`.

## pbinspect

`pbpaste` cannot show you what is actually on the clipboard, which makes flavour bugs hard to
reason about. `make inspect` builds and runs a helper that lists every declared type, whether
it holds data, and whether it reads back as a string:

```
$ printf '{\rtf1\ansi hello}' | pbcopy && make inspect
public.rtf                                  18 bytes    "{\rtf1\ansi hello}"
NeXT Rich Text Format v1.0 pasteboard type  18 bytes    "{\rtf1\ansi hello}"
public.utf16-external-plain-text            no data     not readable as string  <-- declared but empty
CorePasteboardFlavorType 0x75743136         no data     not readable as string  <-- declared but empty
public.utf8-plain-text                      no data     not readable as string  <-- declared but empty
NSStringPboardType                          no data     not readable as string  <-- declared but empty
```

That output is why `-t` exists. `pbcopy` declares four plain-text flavours for an RTF payload
and fills none of them, so `pbpaste` finds `public.utf8-plain-text` present, reads nil, and
prints nothing.

It can also write realistic clipboard contents for testing:

```bash
build/pbinspect --write-rtf         # RTF via NSAttributedString, as an editor would
build/pbinspect --write-html-data   # HTML via setData rather than setString
build/pbinspect -pboard find        # inspect a different pasteboard
```

The distinction matters when testing. Writing RTF as a string is not what real applications
do, and it produces a different set of declared flavours than `writeObjects` does.

## Before changing behaviour

[doc/rationale.md](doc/rationale.md) records why each existing behaviour was chosen and what it cost.
Read the relevant entry first; most of them exist because the obvious alternative was tried
and was worse. The one rule with no exceptions is that the locale is never consulted.

## Releasing

See [doc/release-checklist.md](doc/release-checklist.md).
