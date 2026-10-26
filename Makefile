SIM ?= iPhone 17 Pro
# Resolve the name to a UDID so any installed iOS runtime works (a bare name only matches the newest one).
PAREN := (
SIM_ID = $(shell xcrun simctl list devices available | grep -m1 -F '$(SIM) $(PAREN)' | grep -oE '[0-9A-F-]{36}')
APP := build/DerivedData/Build/Products/Debug-iphonesimulator/TalesOfDorlune.app

.PHONY: help project open sim art art-cost art-list credits

help:  ## List commands
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

project:  ## Regenerate TalesOfDorlune.xcodeproj from project.yml
	xcodegen generate

open: project  ## Generate the project and open it in Xcode
	open TalesOfDorlune.xcodeproj

sim: project  ## Build and launch in the iOS Simulator (SIM="iPhone 17 Pro")
	@test -n "$(SIM_ID)" || (echo "No simulator named '$(SIM)'. See: xcrun simctl list devices available" && exit 1)
	xcodebuild -project TalesOfDorlune.xcodeproj -scheme TalesOfDorlune -configuration Debug \
		-destination 'id=$(SIM_ID)' -derivedDataPath build/DerivedData -quiet build
	xcrun simctl boot $(SIM_ID) 2>/dev/null || true
	open -a Simulator 2>/dev/null || true
	xcrun simctl install $(SIM_ID) $(APP)
	xcrun simctl launch --terminate-running-process $(SIM_ID) $$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' $(APP)/Info.plist)

art:  ## Generate missing sprites with Retro Diffusion (uses credits)
	python3 tools/rd.py generate

art-cost:  ## Show what generating the missing sprites would cost (free)
	python3 tools/rd.py generate --dry-run

art-list:  ## Show every asset in art/assets.json and whether it exists
	python3 tools/rd.py list

credits:  ## Show your Retro Diffusion balance
	python3 tools/rd.py credits
