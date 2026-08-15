APP_NAME = Snap2
BUNDLE = $(APP_NAME).app
BUILD_DIR = build_output
BINARY = $(BUILD_DIR)/$(APP_NAME)
CONTENTS = $(BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources
SDK := $(shell xcrun --show-sdk-path)
# SDK 错配防护：若编译器来自 Xcode.app 而 SDK 解析到 CommandLineTools（CLT 与
# Xcode 版本不一致时会出现，报 "this SDK is not supported by the compiler"），
# 改用 Xcode 自带的 macOS 平台 SDK。命令行显式 `make SDK=...` 优先级最高。
SWIFTC_PATH := $(shell xcrun --find swiftc 2>/dev/null)
XCODE_MACOS_SDK := $(wildcard /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk)
ifneq (,$(findstring Xcode.app,$(SWIFTC_PATH)))
ifneq (,$(findstring CommandLineTools,$(SDK)))
ifdef XCODE_MACOS_SDK
SDK := $(XCODE_MACOS_SDK)
$(info [SDK] xcrun 解析到 CommandLineTools SDK 与 Xcode 工具链不匹配，改用 $(XCODE_MACOS_SDK))
endif
endif
endif
SWIFT_FILES = $(shell find Sources -name "*.swift")

# 默认编译当前机器架构；可显式覆盖：make build ARCH=x86_64
ARCH ?= $(shell uname -m)

.PHONY: build app icon run clean

build:
	@mkdir -p $(BUILD_DIR)
	swiftc -o $(BINARY) \
		-target $(ARCH)-apple-macosx14.0 \
		-sdk $(SDK) \
		-swift-version 5 \
		-O \
		$(SWIFT_FILES)

icon:
	@python3 gen_icon.py

app: build icon
	@rm -rf $(BUNDLE)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp $(BINARY) $(MACOS_DIR)/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@grep -q "CFBundleIconFile" $(CONTENTS)/Info.plist || \
		sed -i '' 's|</dict>|    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>\n</dict>|' $(CONTENTS)/Info.plist
	@cp build_tmp/$(APP_NAME).icns $(RESOURCES_DIR)/AppIcon.icns
	@echo -n "APPL????" > $(CONTENTS)/PkgInfo
	@codesign --force --sign - --entitlements Resources/$(APP_NAME).entitlements $(BUNDLE)
	@echo "$(BUNDLE) created."

run: build
	$(BINARY)

clean:
	rm -rf $(BUILD_DIR) $(BUNDLE) build_tmp
