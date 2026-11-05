APP_NAME   := TouchCursor
BUNDLE_ID  := com.touchcursor.TouchCursor
BUILD      := build
APP        := $(BUILD)/$(APP_NAME).app
INSTALL_DIR:= $(HOME)/Applications
AGENT      := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
UID        := $(shell id -u)

SWIFTC := xcrun swiftc -swift-version 5 -O

.PHONY: build test install uninstall restart log clean

build: $(APP)

ICNS := $(BUILD)/AppIcon.icns

$(ICNS): Resources/make-icon.swift
	rm -rf $(BUILD)/AppIcon.iconset && mkdir -p $(BUILD)/AppIcon.iconset
	xcrun swift Resources/make-icon.swift $(BUILD)/icon_1024.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s $(BUILD)/icon_1024.png --out $(BUILD)/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s * 2)); \
		sips -z $$d $$d $(BUILD)/icon_1024.png --out $(BUILD)/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns $(BUILD)/AppIcon.iconset -o $(ICNS)

$(APP): Sources/*.swift Resources/Info.plist $(ICNS)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	$(SWIFTC) Sources/*.swift -o $(APP)/Contents/MacOS/$(APP_NAME)
	codesign --force --sign - --identifier $(BUNDLE_ID) $(APP)

test:
	mkdir -p $(BUILD)
	$(SWIFTC) Sources/Engine.swift Tests/main.swift -o $(BUILD)/tests
	$(BUILD)/tests

install: build
	-launchctl bootout gui/$(UID)/$(BUNDLE_ID) 2>/dev/null
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(APP) $(INSTALL_DIR)/
	sed "s|__EXECUTABLE__|$(INSTALL_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)|; s|__LOG__|$(HOME)/Library/Logs/$(APP_NAME).log|" \
		Resources/LaunchAgent.plist > $(AGENT)
	launchctl bootstrap gui/$(UID) $(AGENT)
	@echo "Installed. Grant Accessibility access to TouchCursor when prompted"
	@echo "(System Settings > Privacy & Security > Accessibility)."

uninstall:
	-launchctl bootout gui/$(UID)/$(BUNDLE_ID)
	rm -f $(AGENT)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app

restart:
	launchctl kickstart -k gui/$(UID)/$(BUNDLE_ID)

log:
	tail -f $(HOME)/Library/Logs/$(APP_NAME).log

clean:
	rm -rf $(BUILD)
