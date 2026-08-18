# utfcopy

`utfcopy` and `utfpaste` move text between the shell and the macOS clipboard. They are
drop-in replacements for `pbcopy` and `pbpaste` that do not depend on the locale, so Unicode
survives in environments where the originals corrupt it.

[Installation](#installation) • [Usage](#usage) • [Why](#why) • [Caveats](#quirks-and-caveats)

## Features

* Encoding never depends on `LANG`, `LC_ALL` or `LC_CTYPE`.
* Correct for emoji, CJK, combining marks, ZWJ sequences, RTL text and astral plane characters.
* Accepts `pbcopy` and `pbpaste` flags, so existing scripts work after an alias.
* `-t` selects the pasteboard flavour, which `pbpaste` lists as a limitation in its own man page.
* Exits non-zero on invalid input, so nothing lossy reaches the clipboard.
* One Swift file, no dependencies beyond system AppKit, a 114 KB binary.

## Demo

```bash
$ echo "Hello ✅ 日本語 🎉" | utfcopy
$ utfpaste
Hello ✅ 日本語 🎉
```

The difference shows up where the locale is not set, as in a launch agent, cron job or CI
runner. `env -i` simulates that:

```bash
$ printf 'Hello ✅ 日本語 🎉' | env -i pbcopy  && pbpaste
Hello ‚úÖ Êó•Êú¨Ë™û üéâ
$ printf 'Hello ✅ 日本語 🎉' | env -i utfcopy && utfpaste
Hello ✅ 日本語 🎉
```

## Installation

```bash
brew tap prog893/tap
brew install utfcopy
```

Installs both commands. Requires macOS 12 (Monterey) or later.

To replace the system tools everywhere:

```bash
alias pbcopy=utfcopy
alias pbpaste=utfpaste
```

## Usage

```bash
utfcopy  [options]        # stdin to the clipboard
utfpaste [options]        # clipboard to stdout
```

| Option | Mode | Meaning |
| --- | --- | --- |
| `-t`, `--type <flavor>` | both | `string` (default), `html`, `rtf`, `ps` |
| `-pboard <board>` | both | `general` (default), `ruler`, `find`, `font`, `drag` |
| `-Prefer <txt\|rtf\|ps>` | paste | accepted for compatibility |
| `-h`, `--help`, `-help` | both | usage |
| `-V`, `--version` | both | version |

```bash
# No trailing newline is added, so command substitution round-trips exactly
$ printf 'v1.2.3' | utfcopy
$ [ "$(utfpaste)" = "v1.2.3" ] && echo exact
exact

# Copy a file
$ utfcopy < notes.md

# Tag as HTML so a rich-text app renders it instead of showing the tags
$ echo '<b>bold</b> and <i>italic</i>' | utfcopy -t html

# Strip formatting from something copied out of a browser
$ utfpaste -t string
```

Scope matches `pbcopy` and `pbpaste`: stdin in, stdout out. Two separate binaries, built from
one source file with the mode compiled in. Both share the system pasteboard with the
originals, so they interoperate in either direction.

`-pboard` and `-Prefer` are accepted unchanged, including the deprecated `ascii` alias for
`txt` and the undocumented `drag` pasteboard.

Pasteboard entries carry a tag describing what kind of content they hold, and receiving apps
use it to decide how to interpret the bytes. `-t` sets that tag on copy and selects it on
paste, which is why the two `-t` examples above behave differently from their untagged
equivalents.

## Why

`pbcopy` picks its encoding from the locale environment variables. From its own man page:

> If an encoding cannot be determined from the locale, the standard C encoding will be used.

Launch agents, cron jobs, Docker `exec`, CI runners, editor subprocesses, an AI agent's bash
tool and `ssh` without `SendEnv` all start with a stripped or partial environment. In that
state `pbcopy` reads UTF-8 as MacRoman and corrupts every non-ASCII character.

It looks fine from the shell that did it, because `pbpaste` reverses the mistake with the
same wrong encoding:

```bash
$ printf '日本語' | env -i pbcopy
$ env -i pbpaste
日本語                 # looks correct
$ pbpaste              # what every GUI app actually sees
Êó•Êú¨Ë™û
```

You find out when the text reaches Slack, a browser form, or a commit message.

Setting `LANG` fixes the case where you control the environment, not the case that breaks:
you cannot `export` your way out of a launchd plist, another program's `posix_spawn`, or a CI
image you do not own. A shell function covers interactive shells only, and nothing spawning
`/usr/bin/pbcopy` directly sees it. `iconv` addresses a different problem, since `pbcopy` is
not mis-transcoding valid input, it is assuming the wrong source encoding.

`utfcopy` never asks the locale. It decodes stdin as UTF-8 and hands a `String` to
`NSPasteboard`, which stores UTF-16, so there is no encoding to negotiate and nothing to
configure.

## Quirks and caveats

* Invalid UTF-8 exits 1 and leaves the clipboard untouched, rather than copying something
  lossy. Convert deliberately instead: `iconv -f windows-1252 -t utf-8 | utfcopy`.
* Unknown options exit 1. `pbcopy` ignores what it does not recognise and still exits 0, so
  `pbcopy --typo` copies anyway; here a misspelled flag fails loudly.
* `-t html` and `-t rtf` write only the named flavour, so a plain-text target pastes nothing.
  `pbcopy` leaves an empty plain-text entry behind instead, which is why `pbpaste` cannot read
  its own RTF.
* A UTF-8 BOM is stripped rather than copied through as U+FEFF, and UTF-16 input is decoded
  when it carries a BOM. `pbcopy` handles neither.
* No trailing newline is added on paste, and with no `-t` a payload starting with `{\rtf` or
  an EPS header is stored as that flavour. Both match `pbcopy`.

[doc/rationale.md](doc/rationale.md) covers why each of these behaves this way and what it costs.

## Development

```bash
make build
make test
sudo make install     # to /usr/local/bin (override with PREFIX=)
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. Tamirlan Torgayev ([@prog893](https://github.com/prog893)).
