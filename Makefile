APP := MonitorBar.app
ZIP := MonitorBar.zip

.PHONY: build run test icon app screenshot dist clean

build:
	swift build

run:
	swift run MonitorBar

test:
	swift test

icon:
	swift Scripts/generate-icon.swift

app:
	Scripts/make-app.sh

screenshot:
	swift run SnapshotTool Docs/screenshot.png

dist: app
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(ZIP)"
	@echo "Wrote $(ZIP)"

clean:
	rm -rf .build "$(APP)" "$(ZIP)"
