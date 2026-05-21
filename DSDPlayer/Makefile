.PHONY: gen open clean

gen:
	@command -v xcodegen >/dev/null || { echo "Install xcodegen: brew install xcodegen"; exit 1; }
	xcodegen generate

open: gen
	open DSDPlayer.xcodeproj

clean:
	rm -rf DSDPlayer.xcodeproj build DerivedData
