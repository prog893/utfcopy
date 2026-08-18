// utfcopy / utfpaste
//
// Locale-independent replacements for pbcopy and pbpaste.
//
// pbcopy decides its input encoding from the locale environment variables. When
// the locale chain is broken (sandboxes, launch agents, cron, `env -i`, ssh
// without SendEnv) it falls back to the C encoding and stores non-ASCII input as
// MacRoman, so "Hello ✅" reaches other apps as "Hello ‚úÖ".
//
// This tool never consults the locale. Bytes are decoded as UTF-8 and handed to
// NSPasteboard, which stores them as UTF-16 internally, so what lands on the
// pasteboard is exactly what a GUI app reads back.
//
// Scope is deliberately limited to what pbcopy and pbpaste do. The only addition
// is -t/--type, which on paste fixes the limitation pbpaste lists in its own man
// page under BUGS: "There is no way to tell pbpaste to get only a specified data
// type."
//
// This file compiles twice, once per command. utfpaste is built with
// -D PASTE_MODE, so each binary is independent and contains only its own code
// path. Nothing is decided at run time from argv[0]: renaming or copying either
// binary cannot change what it does.

import AppKit

let version = "1.0.0"

// MARK: - Exit codes

enum ExitCode: Int32 {
    case ok = 0
    case input = 1       // could not read or decode input, or bad usage
    case pasteboard = 2  // the pasteboard refused the write
}

enum Mode {
    case copy
    case paste
}

#if PASTE_MODE
let mode: Mode = .paste
let toolName = "utfpaste"
#else
let mode: Mode = .copy
let toolName = "utfcopy"
#endif

func die(_ message: String, _ code: ExitCode) -> Never {
    FileHandle.standardError.write(Data("\(toolName): \(message)\n".utf8))
    exit(code.rawValue)
}

// MARK: - Pasteboard flavours

/// The content flavours we can put on, or pull off, the pasteboard.
enum Flavor: String {
    case string
    case html
    case rtf
    case ps

    var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .string: return .string  // public.utf8-plain-text
        case .html: return .html      // public.html
        case .rtf: return .rtf        // public.rtf
        case .ps: return NSPasteboard.PasteboardType("com.adobe.encapsulated-postscript")
        }
    }

    static func parse(_ raw: String) -> Flavor? {
        switch raw.lowercased() {
        case "string", "text", "txt", "plain": return .string
        case "html": return .html
        case "rtf": return .rtf
        // pbpaste spells EPS "ps"; "ascii" is its deprecated alias for plain text.
        case "ps", "eps", "postscript": return .ps
        case "ascii": return .string
        default: return nil
        }
    }
}

func pasteboard(named raw: String) -> NSPasteboard? {
    switch raw.lowercased() {
    case "general": return .general
    case "ruler": return NSPasteboard(name: .ruler)
    case "find": return NSPasteboard(name: .find)
    case "font": return NSPasteboard(name: .font)
    case "drag": return NSPasteboard(name: .drag)
    default: return nil
    }
}

// MARK: - Usage

#if PASTE_MODE
let synopsis = """
USAGE
  utfpaste [options]            write the clipboard to stdout

OPTIONS
  -t, --type <flavor>     read only this flavour: string (default), html, rtf, ps
  -h, --help, -help       show this help
  -V, --version           show the version

FROM pbpaste
  -pboard <board>         general (default), ruler, find, font, drag
  -Prefer <txt|rtf|ps>    flavour to look for first, then fall back
"""
let notes = """
  Output is the pasteboard's bytes with no trailing newline added, matching
  pbpaste, so $(utfpaste) round-trips exactly.

  -t reads one flavour and nothing else. pbpaste cannot do this; its own man
  page lists it under BUGS, and -Prefer does not substitute for it. An absent
  flavour prints nothing and still exits 0.
"""
#else
let synopsis = """
USAGE
  utfcopy [options]             read stdin into the clipboard

OPTIONS
  -t, --type <flavor>     store as this flavour: string (default), html, rtf, ps
  -h, --help, -help       show this help
  -V, --version           show the version

FROM pbcopy
  -pboard <board>         general (default), ruler, find, font, drag
"""
let notes = """
  Unlike pbcopy, the encoding never depends on LANG, LC_ALL or LC_CTYPE.
  Input is decoded as UTF-8 (UTF-8 and UTF-16 BOMs are honoured) and handed to
  NSPasteboard, which stores it as UTF-16. Invalid UTF-8 is an error rather
  than silently replaced, so mojibake cannot reach the clipboard.

  With no -t, a payload starting with an RTF or EPS header is stored as that
  flavour, matching pbcopy. Use -t string to force plain text.
"""
#endif

let usage = """
\(toolName) \(version) - pbcopy and pbpaste without the encoding bugs.

\(synopsis)

EXIT CODES
  0  success
  1  input could not be read or decoded as UTF-8, or bad usage
  2  the pasteboard rejected the write

NOTES
\(notes)
  Unknown options are an error here. pbcopy ignores them and still exits 0.
"""

// MARK: - Argument parsing

// There are no copy/paste subcommands: two commands for two jobs, as with pbcopy
// and pbpaste. A `utfpaste copy` spelling would let a paste invocation clear the
// clipboard, which is not a mistake worth enabling. The mode itself is set at the
// top of this file, at compile time.
var flavor: Flavor?  // nil means "not specified"
var preferOrder: [Flavor] = []
var board: NSPasteboard = .general

let args = Array(CommandLine.arguments.dropFirst())

/// Pulls the value for a flag, accepting both `--flag value` and `--flag=value`.
func takeValue(_ flag: String, _ inlineValue: String?, _ index: inout Int) -> String {
    if let inlineValue { return inlineValue }
    index += 1
    guard index < args.count else {
        die("option \(flag) requires a value", .input)
    }
    return args[index]
}

var i = 0
while i < args.count {
    let arg = args[i]

    // Split --flag=value once, so every case below can share it.
    var name = arg
    var inlineValue: String?
    if arg.hasPrefix("-"), let eq = arg.firstIndex(of: "=") {
        name = String(arg[arg.startIndex..<eq])
        inlineValue = String(arg[arg.index(after: eq)...])
    }

    switch name {
    case "-h", "--help", "-help":
        print(usage)
        exit(ExitCode.ok.rawValue)

    case "-V", "--version", "-version":
        print("\(toolName) \(version)")
        exit(ExitCode.ok.rawValue)

    case "-t", "--type":
        let raw = takeValue(name, inlineValue, &i)
        guard let parsed = Flavor.parse(raw) else {
            die("unknown type '\(raw)' (want: string, html, rtf, ps)", .input)
        }
        flavor = parsed

    // pbpaste-only, so utfcopy rejects it rather than accepting a no-op.
    case "-Prefer", "-prefer", "--prefer":
        guard mode == .paste else {
            die("-Prefer applies to pasting only", .input)
        }
        let raw = takeValue(name, inlineValue, &i)
        guard let parsed = Flavor.parse(raw) else {
            die("unknown -Prefer value '\(raw)' (want: txt, rtf, ps)", .input)
        }
        preferOrder.append(parsed)

    case "-pboard", "--pboard":
        let raw = takeValue(name, inlineValue, &i)
        guard let parsed = pasteboard(named: raw) else {
            die("unknown pasteboard '\(raw)' (want: general, ruler, find, font, drag)", .input)
        }
        board = parsed

    default:
        die("unknown option '\(arg)' (try \(toolName) --help)", .input)
    }
    i += 1
}

// MARK: - Decoding

/// Decodes bytes to a String without ever consulting the locale.
///
/// Honours a UTF-8 or UTF-16 BOM, then requires strict UTF-8. Refusing invalid
/// input is deliberate: a lossy decode is exactly the mojibake this tool exists
/// to prevent, and it would be silent whenever stderr is discarded.
func decode(_ data: Data) -> String {
    if data.isEmpty { return "" }

    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
        let body = data.dropFirst(3)
        if let s = String(data: body, encoding: .utf8) { return s }
    }

    // UTF-16 bodies must be a whole number of code units. Swift's decoder
    // silently discards a dangling odd byte, which would be exactly the quiet
    // corruption this tool exists to prevent, so check the length first.
    for (bom, encoding) in [([0xFF, 0xFE] as [UInt8], String.Encoding.utf16LittleEndian),
                            ([0xFE, 0xFF] as [UInt8], String.Encoding.utf16BigEndian)] {
        guard data.starts(with: bom) else { continue }
        let body = data.dropFirst(2)
        if body.count % 2 != 0 {
            die("input has a UTF-16 BOM but an odd byte count (\(body.count)); it is truncated. Nothing was copied.", .input)
        }
        guard let s = String(data: body, encoding: encoding) else {
            die("input has a UTF-16 BOM but is not valid UTF-16. Nothing was copied.", .input)
        }
        return s
    }

    if let s = String(data: data, encoding: .utf8) { return s }

    die("""
        input is not valid UTF-8. Nothing was copied.
        Convert it first, for example: iconv -f windows-1252 -t utf-8 | \(toolName)
        """, .input)
}

/// Chooses the flavour for a payload the way pbcopy does when no type is given.
func sniffFlavor(_ text: String) -> Flavor {
    if text.hasPrefix("{\\rtf") { return .rtf }
    if text.hasPrefix("%!PS-Adobe"), text.contains("EPSF") { return .ps }
    return .string
}

// MARK: - Copy

func runCopy() -> Never {
    // Read to EOF. availableData returns empty only at end of stream, so this
    // survives a payload arriving in chunks from a slow pipe.
    var data = Data()
    let stdin = FileHandle.standardInput
    while true {
        let chunk = stdin.availableData
        if chunk.isEmpty { break }
        data.append(chunk)
    }

    let text = decode(data)
    let chosen = flavor ?? sniffFlavor(text)

    board.clearContents()
    guard board.setString(text, forType: chosen.pasteboardType) else {
        die("pasteboard rejected \(chosen.pasteboardType.rawValue)", .pasteboard)
    }

    exit(ExitCode.ok.rawValue)
}

// MARK: - Paste

func readPasteboard() -> String? {
    // An explicit -t means "only this flavour", which is the pbpaste limitation
    // called out in its own man page. Otherwise try the -Prefer order, then fall
    // back the way pbpaste does.
    if let flavor {
        return board.string(forType: flavor.pasteboardType)
    }
    var order = preferOrder
    for fallback in [Flavor.string, .ps, .rtf] where !order.contains(fallback) {
        order.append(fallback)
    }
    for candidate in order {
        if let s = board.string(forType: candidate.pasteboardType) { return s }
    }
    return nil
}

func runPaste() -> Never {
    guard let text = readPasteboard() else {
        // pbpaste prints nothing and still succeeds when the flavour is absent.
        exit(ExitCode.ok.rawValue)
    }

    // Write UTF-8 bytes directly. print() would append a newline that pbpaste
    // does not add, which breaks `$(utfpaste)` round-trips.
    FileHandle.standardOutput.write(Data(text.utf8))
    exit(ExitCode.ok.rawValue)
}

// MARK: - Dispatch

switch mode {
case .copy: runCopy()
case .paste: runPaste()
}
