# Command Line Tools ship the Swift Testing macro plugin in a subfolder SwiftPM doesn't search.
TESTING_PLUGINS := $(wildcard /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing)
TEST_FLAGS := $(if $(TESTING_PLUGINS),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS),)

.PHONY: build test pkg icon social clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

pkg:
	./packaging/build.sh

icon:
	swift packaging/icon/make-icon.swift

social:
	swift packaging/icon/make-social.swift

clean:
	rm -rf .build dist
