PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
BUILD  := build
COPY   := $(BUILD)/utfcopy
PASTE  := $(BUILD)/utfpaste
SRC    := Sources/utfcopy/main.swift

# Build for the host architecture, floored at macOS 12 (Monterey).
ARCH       := $(shell uname -m)
DEPLOY     := 12.0
SWIFTFLAGS := -O -target $(ARCH)-apple-macos$(DEPLOY)

# utfpaste is the same source compiled with the paste mode selected, so the two
# binaries are independent and neither looks at argv[0].
PASTEFLAG := -D PASTE_MODE

.PHONY: all build universal install uninstall test inspect clean

all: build

build: $(COPY) $(PASTE)

$(COPY): $(SRC)
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -o $@ $(SRC)

$(PASTE): $(SRC)
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) $(PASTEFLAG) -o $@ $(SRC)

# Development helper. Dumps every declared pasteboard type and whether it holds
# data, which is the only way to see pbcopy declaring plain-text flavours it
# never fills. Not installed.
$(BUILD)/pbinspect: scripts/pbinspect.swift
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -o $@ scripts/pbinspect.swift

inspect: $(BUILD)/pbinspect
	@$(BUILD)/pbinspect

# Fat binaries for distribution, so one bottle covers Apple silicon and Intel.
universal: $(SRC)
	@mkdir -p $(BUILD)
	swiftc -O -target arm64-apple-macos$(DEPLOY)  -o $(BUILD)/utfcopy-arm64 $(SRC)
	swiftc -O -target x86_64-apple-macos$(DEPLOY) -o $(BUILD)/utfcopy-x86_64 $(SRC)
	lipo -create -output $(COPY) $(BUILD)/utfcopy-arm64 $(BUILD)/utfcopy-x86_64
	swiftc -O -target arm64-apple-macos$(DEPLOY)  $(PASTEFLAG) -o $(BUILD)/utfpaste-arm64 $(SRC)
	swiftc -O -target x86_64-apple-macos$(DEPLOY) $(PASTEFLAG) -o $(BUILD)/utfpaste-x86_64 $(SRC)
	lipo -create -output $(PASTE) $(BUILD)/utfpaste-arm64 $(BUILD)/utfpaste-x86_64
	@rm -f $(BUILD)/utfcopy-arm64 $(BUILD)/utfcopy-x86_64
	@rm -f $(BUILD)/utfpaste-arm64 $(BUILD)/utfpaste-x86_64
	@lipo -info $(COPY) $(PASTE)

install: build
	install -d $(BINDIR)
	install -m 0755 $(COPY) $(BINDIR)/utfcopy
	install -m 0755 $(PASTE) $(BINDIR)/utfpaste
	@echo "installed utfcopy and utfpaste to $(BINDIR)"

uninstall:
	rm -f $(BINDIR)/utfcopy $(BINDIR)/utfpaste
	@echo "removed utfcopy and utfpaste from $(BINDIR)"

test: build $(BUILD)/pbinspect
	@./tests/run.sh

clean:
	rm -rf $(BUILD) .build
