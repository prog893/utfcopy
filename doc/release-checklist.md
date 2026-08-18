# Release checklist

The Homebrew formula lives in [prog893/homebrew-tap](https://github.com/prog893/homebrew-tap)
and builds from source at a git tag pinned to a revision, so a release is a tag here plus a
formula bump there.

1. Bump `version` in `Sources/utfcopy/main.swift`.

2. Verify on a clean tree:

   ```bash
   make clean && make test
   make universal        # confirms both architectures still compile
   ```

3. Commit the version bump, then tag and push:

   ```bash
   git tag -a v1.0.1 -m "utfcopy 1.0.1"
   git push origin main --follow-tags
   ```

4. Get the revision the formula should pin:

   ```bash
   git rev-parse v1.0.1
   ```

5. Update `Formula/utfcopy.rb` in the tap with the new `version`, `tag` and `revision`, then
   commit as `utfcopy 1.0.1`.

6. Verify the formula builds from a clean checkout rather than the working tree:

   ```bash
   brew update
   brew install --build-from-source prog893/tap/utfcopy
   utfcopy --version
   printf 'release check ✅ 日本語' | utfcopy && utfpaste
   ```

   The last line exercises both binaries, which is worth doing explicitly: they are separate
   executable targets, so a formula that installs only one still passes a `utfcopy --version`
   check.

Two constraints the formula depends on, both found by installing rather than by reading:

- No `depends_on xcode:`. That requirement demands a full Xcode.app and refuses to build
  against the Command Line Tools, which are sufficient here.
- `swift build` needs `--disable-sandbox`. SwiftPM sandboxes its own manifest compile, and
  nesting that inside Homebrew's sandbox fails with `sandbox_apply: Operation not permitted`,
  surfaced as `Invalid manifest`.
