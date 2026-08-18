// swift-tools-version:5.10
import PackageDescription

// Two executables from one source file. utfpaste is built with -D PASTE_MODE, so
// each binary contains only its own code path and neither inspects argv[0].
//
// Sources/utfpaste/main.swift is a git symlink (mode 120000) to the utfcopy
// source, because SwiftPM requires a distinct path per target and refuses to let
// two targets share one directory.
let package = Package(
    name: "utfcopy",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "utfcopy",
            path: "Sources/utfcopy"
        ),
        .executableTarget(
            name: "utfpaste",
            path: "Sources/utfpaste",
            swiftSettings: [.define("PASTE_MODE")]
        ),
    ]
)
