// pbinspect - development helper, not part of the shipped tool.
//
// Prints what is actually on a pasteboard: every declared type, whether it holds
// data, and whether string(forType:) can read it. pbpaste cannot show any of
// this, and the distinction matters: pbcopy declares public.utf8-plain-text when
// storing RTF and then never fills it, which is why pbpaste prints nothing for
// its own RTF.
//
// It can also write RTF the way a real application does, as an attributed string
// via writeObjects, so the reader matrix can be checked against realistic
// clipboard contents rather than only synthetic ones.
//
// Build: make inspect  (or: swiftc -O -o build/pbinspect scripts/pbinspect.swift)
//
// Usage:
//   pbinspect                 dump the general pasteboard
//   pbinspect -pboard find    dump another pasteboard
//   pbinspect --write-rtf     put real app-style RTF on the clipboard, then dump

import AppKit

func board(named raw: String) -> NSPasteboard? {
    switch raw.lowercased() {
    case "general": return .general
    case "ruler": return NSPasteboard(name: .ruler)
    case "find": return NSPasteboard(name: .find)
    case "font": return NSPasteboard(name: .font)
    case "drag": return NSPasteboard(name: .drag)
    default: return nil
    }
}

var pb = NSPasteboard.general
var writeRTF = false
var writeHTMLData = false

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "-pboard", "--pboard":
        i += 1
        guard i < args.count, let b = board(named: args[i]) else {
            FileHandle.standardError.write(Data("pbinspect: bad -pboard value\n".utf8))
            exit(1)
        }
        pb = b
    case "--write-rtf":
        writeRTF = true
    case "--write-html-data":
        writeHTMLData = true
    case "-h", "--help":
        print("""
        pbinspect - dump pasteboard types and readability

          -pboard <name>      general (default), ruler, find, font, drag
          --write-rtf         write app-style RTF (NSAttributedString) first
          --write-html-data   write HTML as data rather than as a string
        """)
        exit(0)
    default:
        FileHandle.standardError.write(Data("pbinspect: unknown option \(args[i])\n".utf8))
        exit(1)
    }
    i += 1
}

if writeRTF {
    // How a real editor puts RTF on the clipboard: an attributed string written
    // through writeObjects, which fills both the rich and plain flavours.
    let attributed = NSMutableAttributedString(
        string: "bold unicode ✅ 日本語",
        attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
    )
    pb.clearContents()
    pb.writeObjects([attributed])
    print("wrote app-style RTF via NSAttributedString/writeObjects\n")
}

if writeHTMLData {
    let html = "<b>html as data ✅</b>"
    pb.clearContents()
    pb.declareTypes([.html], owner: nil)
    pb.setData(Data(html.utf8), forType: .html)
    print("wrote HTML via setData\n")
}

guard let types = pb.types, !types.isEmpty else {
    print("pasteboard is empty (changeCount \(pb.changeCount))")
    exit(0)
}

print("changeCount \(pb.changeCount), \(types.count) declared type(s)\n")

let nameWidth = types.map(\.rawValue.count).max() ?? 20

for type in types {
    let data = pb.data(forType: type)
    let string = pb.string(forType: type)

    // A type can be declared yet hold nothing. That is the pbcopy RTF case, and
    // it is exactly what pbpaste trips over.
    let dataDesc: String
    switch data {
    case .none: dataDesc = "no data"
    case .some(let d) where d.isEmpty: dataDesc = "0 bytes"
    case .some(let d): dataDesc = "\(d.count) bytes"
    }

    let stringDesc: String
    switch string {
    case .none: stringDesc = "not readable as string"
    case .some(let s):
        let flat = s.replacingOccurrences(of: "\n", with: "\\n")
        let shown = flat.count > 40 ? String(flat.prefix(40)) + "..." : flat
        stringDesc = "\"\(shown)\""
    }

    let padded = type.rawValue.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
    let flag = (data == nil && string == nil) ? "  <-- declared but empty" : ""
    print("\(padded)  \(dataDesc.padding(toLength: 10, withPad: " ", startingAt: 0))  \(stringDesc)\(flag)")
}
