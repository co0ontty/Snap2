APP_NAME = Snap2
BUNDLE = $(APP_NAME).app
BUILD_DIR = build_output
BINARY = $(BUILD_DIR)/$(APP_NAME)
CONTENTS = $(BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources
SDK = $(shell xcrun --show-sdk-path)
SWIFT_FILES = $(shell find Sources -name "*.swift")

.PHONY: build app icon run clean

build:
	@mkdir -p $(BUILD_DIR)
	swiftc -o $(BINARY) \
		-target arm64-apple-macosx14.0 \
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
