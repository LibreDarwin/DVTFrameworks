#
# Makefile
# DVTFrameworks
#
# Copyright (C) 2026, LibreDarwin
# All rights reserved.
#

.PHONY: all frameworks test clean install install-release

DEVELOPER_DIR ?= /Users/sunneva/xnuports-root/devel/xcode-tools/build/release/Developer
TOOLCHAIN_BIN := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin
# Build against Apple's SDK by default. The reduced Internal SDK under
# $(DEVELOPER_DIR) also works and can be selected with `make SDK_PATH=...`.
SDK_PATH ?= /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

CC := $(TOOLCHAIN_BIN)/clang
SWIFT := $(TOOLCHAIN_BIN)/swiftc
# The Swift overlay test is skipped rather than failing on a toolchain without Swift.
HAVE_SWIFT := $(shell test -x $(SWIFT) && echo yes || echo no)

CURRENT_VERSION := 1.0.0
COMPATIBILITY_VERSION := 1.0.0

SRC_DIR := src
# Headers here are shared by every framework; anything a single framework
# declares belongs in that framework's own include directory.
COMMON_INC_DIR := include
TEST_DIR := tests
BUILD_DIR := build

# Every framework with sources under src/ is built. The list is discovered
# rather than hard-coded so a new framework only needs a directory.
FRAMEWORKS := $(sort $(foreach f,$(wildcard $(SRC_DIR)/*/*.m),\
	$(firstword $(subst /, ,$(patsubst $(SRC_DIR)/%,%,$(f))))))
FRAMEWORK_TARGETS := $(foreach fw,$(FRAMEWORKS),$(BUILD_DIR)/$(fw).framework/Versions/A/$(fw))

WARNINGS := -Wall -Wextra -Wno-unused-parameter -Wobjc-missing-property-synthesis
CFLAGS := -fobjc-arc -fPIC -O2 -g $(WARNINGS)
CFLAGS += -isysroot $(SDK_PATH) -I$(COMMON_INC_DIR) -DDEBUG=1
LDFLAGS := -isysroot $(SDK_PATH) -framework Foundation -framework CoreFoundation -lz

TEST_BIN := $(BUILD_DIR)/dvt_tests

# Apple's DVTFoundation ships no module map, so Swift reaches the framework
# through a bridging header rather than `import DVTFoundation`.
BRIDGING_HEADER := $(TEST_DIR)/DVTFoundation-Bridging-Header.h
SWIFT_TEST_BIN := $(BUILD_DIR)/dvt_swift_overlay_test

# Include search path for a framework's own headers plus the common ones.
fw_includes = -I$(COMMON_INC_DIR) $(foreach d,$(wildcard $(SRC_DIR)/$(1)/include),-I$(d))
# The compiled objects for one framework, one per source file.
fw_objects = $(patsubst $(SRC_DIR)/$(1)/%.m,$(BUILD_DIR)/obj/$(1)/%.o,$(wildcard $(SRC_DIR)/$(1)/*.m))
# The headers whose contents can change a framework's objects.
fw_headers = $(wildcard $(SRC_DIR)/$(1)/include/*.h) $(wildcard $(COMMON_INC_DIR)/*.h)

all: frameworks

frameworks: $(FRAMEWORK_TARGETS)

# $(BUILD_DIR)/obj/<framework>/%.o compiles one source of one framework.
# A pattern rule cannot match both the framework and the file name, so the
# per-source rules are generated from each framework's file list instead.
define DVT_OBJECT_RULE
$(BUILD_DIR)/obj/$(1)/$(2).o: $(SRC_DIR)/$(1)/$(2).m $$(call fw_headers,$(1)) Makefile
	@mkdir -p $$(dir $$@)
	$$(CC) $$(CFLAGS) $$(call fw_includes,$(1)) -c $$< -o $$@
endef

$(foreach fw,$(FRAMEWORKS),\
	$(foreach src,$(patsubst $(SRC_DIR)/$(fw)/%.m,%,$(wildcard $(SRC_DIR)/$(fw)/*.m)),\
		$(eval $(call DVT_OBJECT_RULE,$(fw),$(src)))))

# The dylib lives inside the bundle; the top-level symlinks point at it.
#
# A pattern rule cannot name the framework twice, so these are generated per
# framework. The bundle is written in one recipe because a dylib cannot be
# created atomically across several make targets, and an interrupted link would
# otherwise leave a half-written framework that make considers up to date.
define DVT_FRAMEWORK_RULE
$(BUILD_DIR)/$(1).framework/Versions/A/$(1): $$(call fw_objects,$(1)) $$(call fw_headers,$(1)) Makefile
	@mkdir -p $(BUILD_DIR)/$(1).framework/Versions/A/Headers \
		$(BUILD_DIR)/$(1).framework/Versions/A/Resources
	$$(CC) -dynamiclib -install_name @rpath/$(1).framework/Versions/A/$(1) \
		-compatibility_version $$(COMPATIBILITY_VERSION) \
		-current_version $$(CURRENT_VERSION) \
		$$(LDFLAGS) -o $$@ $$(call fw_objects,$(1))
	@cp $$(wildcard $$(SRC_DIR)/$(1)/include/*.h) $$(wildcard $$(COMMON_INC_DIR)/*.h) \
		$$(BUILD_DIR)/$(1).framework/Versions/A/Headers/
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'	<key>CFBundleDevelopmentRegion</key>' \
		'	<string>en</string>' \
		'	<key>CFBundleExecutable</key>' \
		'	<string>$(1)</string>' \
		'	<key>CFBundleIdentifier</key>' \
		'	<string>org.libredarwin.$(1)</string>' \
		'	<key>CFBundleInfoDictionaryVersion</key>' \
		'	<string>6.0</string>' \
		'	<key>CFBundleName</key>' \
		'	<string>$(1)</string>' \
		'	<key>CFBundlePackageType</key>' \
		'	<string>FMWK</string>' \
		'	<key>CFBundleShortVersionString</key>' \
		'	<string>$$(CURRENT_VERSION)</string>' \
		'	<key>CFBundleVersion</key>' \
		'	<string>$$(COMPATIBILITY_VERSION)</string>' \
		'</dict>' \
		'</plist>' > $$(@D)/Resources/Info.plist
	@rm -rf $$(BUILD_DIR)/$(1).framework/Versions/Current \
		$$(BUILD_DIR)/$(1).framework/Versions/A/A
	@ln -sfn A $$(BUILD_DIR)/$(1).framework/Versions/Current
	@ln -sfn Versions/A/$(1) $$(BUILD_DIR)/$(1).framework/$(1)
	@ln -sfn Versions/Current/Headers $$(BUILD_DIR)/$(1).framework/Headers
	@ln -sfn Versions/Current/Resources $$(BUILD_DIR)/$(1).framework/Resources
	@codesign -f -s - $$(BUILD_DIR)/$(1).framework 2>/dev/null || true
	@echo "built $$(BUILD_DIR)/$(1).framework"
endef

$(foreach fw,$(FRAMEWORKS),$(eval $(call DVT_FRAMEWORK_RULE,$(fw))))

DVTFOUNDATION_BIN := $(BUILD_DIR)/DVTFoundation.framework/Versions/A/DVTFoundation
DVTFOUNDATION_INCLUDES := $(call fw_includes,DVTFoundation)

$(TEST_BIN): $(TEST_DIR)/dvt_tests.m $(DVTFOUNDATION_BIN) Makefile
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(DVTFOUNDATION_INCLUDES) $< -o $@ \
		$(DVTFOUNDATION_BIN) \
		-Wl,-rpath,$(abspath $(BUILD_DIR)) \
		$(LDFLAGS)

$(SWIFT_TEST_BIN): $(TEST_DIR)/dvt_swift_overlay_test.swift $(BRIDGING_HEADER) $(DVTFOUNDATION_BIN) Makefile
	@mkdir -p $(dir $@)
	$(SWIFT) -import-objc-header $(BRIDGING_HEADER) \
		$(DVTFOUNDATION_INCLUDES) -sdk $(SDK_PATH) \
		$(TEST_DIR)/dvt_swift_overlay_test.swift -o $@ \
		$(DVTFOUNDATION_BIN) \
		-Xlinker -rpath -Xlinker $(abspath $(BUILD_DIR))

ifeq ($(HAVE_SWIFT),yes)
test: $(TEST_BIN) $(SWIFT_TEST_BIN)
	@$(TEST_BIN)
	@$(SWIFT_TEST_BIN)
else
test: $(TEST_BIN)
	@$(TEST_BIN)
	@echo "note: $(SWIFT) is not executable, skipping the Swift overlay test"
endif

clean:
	rm -rf $(BUILD_DIR)

install: frameworks
	install -d $(DESTDIR)/Library/Frameworks
	@for fw in $(FRAMEWORKS); do \
		echo "installing $$fw"; \
		rm -rf "$(DESTDIR)/Library/Frameworks/$$fw.framework"; \
		cp -R "$(BUILD_DIR)/$$fw.framework" "$(DESTDIR)/Library/Frameworks/"; \
	done

install-release: install
