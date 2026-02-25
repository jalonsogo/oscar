APP_NAME     = OScar
BUNDLE_ID    = com.oscarapp.oscar
VERSION      = 0.1.0
BUILD_DIR    = .build
APP_BUNDLE   = $(BUILD_DIR)/$(APP_NAME).app
BINARY       = $(BUILD_DIR)/release/$(APP_NAME)

.PHONY: build run bundle clean open xcode

## Build release binary
build:
	swift build -c release

## Build the .app bundle (required for proper menu bar + Spotlight behaviour)
bundle: build
	@echo "→ Packaging $(APP_NAME).app"
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Sources/OScar/Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "✓ $(APP_BUNDLE)"

## Run the debug build directly (no dock suppression — use bundle for real usage)
run:
	swift run

## Regenerate OScar.xcodeproj from project.yml (run after adding/removing source files)
## Note: xcodegen overwrites Info.plist with Xcode variable syntax; we restore it immediately.
xcodeproj:
	xcodegen generate
	@git checkout -- Sources/OScar/Resources/Info.plist 2>/dev/null || \
	  echo "⚠ Remember: xcodegen may have overwritten Info.plist — check CFBundleExecutable"

## Open the Xcode project (use this for Spotlight/AppIntents support)
xcode:
	open OScar.xcodeproj

## Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)

## Create the default agent config if it doesn't exist
init-config:
	@mkdir -p ~/.config/oscar
	@[ -f ~/.config/oscar/agent.yaml ] && echo "Config already exists." || \
	  (cp Examples/agent.yaml ~/.config/oscar/agent.yaml && echo "✓ Created ~/.config/oscar/agent.yaml")

## Install the app bundle to /Applications
install: bundle
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -r "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"
	@echo "✓ Installed to /Applications/$(APP_NAME).app"
