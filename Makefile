APP := .build/Crier.app
SIGN_ID ?= -
# A real identity gets a secure timestamp, which notarization requires. Ad-hoc builds skip it so local
# builds never need the network.
TIMESTAMP := $(if $(filter -,$(SIGN_ID)),,--timestamp)
ARCHS ?=
ARCH_FLAGS := $(foreach arch,$(ARCHS),--arch $(arch))
ZIP ?= .build/Crier.zip
DMG ?= .build/Crier.dmg
DMGBUILD ?= dmgbuild
FORMAT_PATHS := Package.swift Sources Tests
# SWIFT_FLAGS adds compiler flags to the app build. The dev target sets CRIER_MEASURE and CRIER_DRILL, and releases
# never do.
SWIFT_FLAGS ?=

ICON := art/app-icon.png
ICONSET := .build/AppIcon.iconset
ICNS := .build/AppIcon.icns

.PHONY: build test lint format app zip dmg run dev clean

build:
	swift build -Xswiftc -warnings-as-errors

test: build
	swift test -Xswiftc -warnings-as-errors

lint:
	xcrun swift-format lint --strict --recursive $(FORMAT_PATHS)

format:
	xcrun swift-format format -i --recursive $(FORMAT_PATHS)

$(ICNS): $(ICON)
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size $(ICON) --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) $(ICON) --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $(ICNS)

app: $(ICNS)
	swift build -c release -Xswiftc -warnings-as-errors $(SWIFT_FLAGS) $(ARCH_FLAGS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release -Xswiftc -warnings-as-errors $(SWIFT_FLAGS) $(ARCH_FLAGS) --show-bin-path)/Crier" \
		$(APP)/Contents/MacOS/Crier
	cp Sources/Crier/Info.plist $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	cp art/glyph.png art/glyph@2x.png art/bell.png $(APP)/Contents/Resources/
	codesign --force --options runtime --entitlements Sources/Crier/Crier.entitlements $(TIMESTAMP) \
		--sign "$(SIGN_ID)" $(APP)

zip: app
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

# dmg refuses a dev build, since make dev writes the same app with the measuring log and the tornado drill.
dmg:
	@if strings $(APP)/Contents/MacOS/Crier | grep -q -e "Crier drill" -e "measuring log failed"; then \
		echo "$(APP) is a dev build. Run make app first."; exit 1; \
	fi
	rm -f $(DMG)
	$(DMGBUILD) -s dmg.py -D app=$(APP) "Crier" $(DMG)
	$(if $(filter-out -,$(SIGN_ID)),codesign --force --sign "$(SIGN_ID)" --timestamp $(DMG))

run: app
	-pkill -x Crier
	open $(APP)

# dev builds and launches the dev app with the measuring log, which writes the biggest headlines of every refresh to
# ~/Library/Application Support/Crier/measure, and the Run Tornado Drill item in the bell menu.
dev:
	$(MAKE) app SWIFT_FLAGS="-Xswiftc -DCRIER_MEASURE -Xswiftc -DCRIER_DRILL"
	-pkill -x Crier
	open $(APP)

clean:
	rm -rf .build
