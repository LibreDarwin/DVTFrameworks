#
# Makefile
# DVTFoundation
#
# Copyright (C) 2026, LibreDarwin
# All rights reserved.
#

.PHONY: all framework clean test install install-release

DEVELOPER_DIR ?= /Users/sunneva/xnuports-root/devel/xcode-tools/build/release/Developer
TOOLCHAIN_BIN := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin
# Build against Apple's SDK by default. The reduced Internal SDK under
# $(DEVELOPER_DIR) also works and can be selected with `make SDK_PATH=...`.
SDK_PATH ?= /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

CC := $(TOOLCHAIN_BIN)/clang

CURRENT_VERSION := 1.0.0
COMPATIBILITY_VERSION := 1.0.0
INSTALL_NAME := @rpath/DVTFoundation.framework/Versions/A/DVTFoundation

SRC_DIR := src
INC_DIR := include
TEST_DIR := tests
BUILD_DIR := build
FRAMEWORK_DIR := $(BUILD_DIR)/DVTFoundation.framework
# The dylib must live inside the bundle: the top-level symlinks point at it.
FRAMEWORK_BIN := $(FRAMEWORK_DIR)/Versions/A/DVTFoundation

SOURCES := $(wildcard $(SRC_DIR)/*.m)
OBJECTS := $(patsubst $(SRC_DIR)/%.m,$(BUILD_DIR)/obj/%.o,$(SOURCES))
HEADERS := $(wildcard $(INC_DIR)/*.h)

WARNINGS := -Wall -Wextra -Wno-unused-parameter -Wobjc-missing-property-synthesis
CFLAGS := -fobjc-arc -fPIC -O2 -g $(WARNINGS)
CFLAGS += -isysroot $(SDK_PATH) -I$(INC_DIR) -DDEBUG=1
LDFLAGS := -isysroot $(SDK_PATH) -framework Foundation -framework CoreFoundation

TEST_BIN := $(BUILD_DIR)/dvt_tests

all: framework

$(BUILD_DIR)/obj/%.o: $(SRC_DIR)/%.m $(HEADERS) Makefile
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

framework: $(FRAMEWORK_BIN)

$(FRAMEWORK_BIN): $(OBJECTS) Makefile
	@mkdir -p $(FRAMEWORK_DIR)/Versions/A/Headers
	@mkdir -p $(FRAMEWORK_DIR)/Versions/A/Resources
	$(CC) -dynamiclib -install_name $(INSTALL_NAME) \
		-compatibility_version $(COMPATIBILITY_VERSION) \
		-current_version $(CURRENT_VERSION) \
		$(LDFLAGS) -o $@ $(OBJECTS)
	@cp $(HEADERS) $(FRAMEWORK_DIR)/Versions/A/Headers/
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'	<key>CFBundleDevelopmentRegion</key>' \
		'	<string>en</string>' \
		'	<key>CFBundleExecutable</key>' \
		'	<string>DVTFoundation</string>' \
		'	<key>CFBundleIdentifier</key>' \
		'	<string>org.libredarwin.DVTFoundation</string>' \
		'	<key>CFBundleInfoDictionaryVersion</key>' \
		'	<string>6.0</string>' \
		'	<key>CFBundleName</key>' \
		'	<string>DVTFoundation</string>' \
		'	<key>CFBundlePackageType</key>' \
		'	<string>FMWK</string>' \
		'	<key>CFBundleShortVersionString</key>' \
		'	<string>$(CURRENT_VERSION)</string>' \
		'	<key>CFBundleVersion</key>' \
		'	<string>$(COMPATIBILITY_VERSION)</string>' \
		'</dict>' \
		'</plist>' > $(FRAMEWORK_DIR)/Versions/A/Resources/Info.plist
	@touch $(FRAMEWORK_DIR)/Versions/A
	@rm -rf $(FRAMEWORK_DIR)/Versions/Current $(FRAMEWORK_DIR)/Versions/A/A
	@ln -sfn A $(FRAMEWORK_DIR)/Versions/Current
	@ln -sfn Versions/Current/DVTFoundation $(FRAMEWORK_DIR)/DVTFoundation
	@ln -sfn Versions/Current/Headers $(FRAMEWORK_DIR)/Headers
	@ln -sfn Versions/Current/Resources $(FRAMEWORK_DIR)/Resources
	@codesign -f -s - $@ 2>/dev/null || true
	@echo "built $@"

$(TEST_BIN): $(TEST_DIR)/dvt_tests.m $(FRAMEWORK_BIN) Makefile
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $< -o $@ \
		$(FRAMEWORK_BIN) \
		-Wl,-rpath,$(abspath $(BUILD_DIR)) \
		$(LDFLAGS)

test: $(TEST_BIN)
	@$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)

install: framework
	install -d $(DESTDIR)/Library/Frameworks
	cp -R $(FRAMEWORK_DIR) $(DESTDIR)/Library/Frameworks/

install-release: install
