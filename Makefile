.PHONY: build clean run release verify

APP := build/3FDragUnstuck.app

build:
	./3FDragUnstuck/build.sh

run: build
	open "$(APP)"

verify: build
	codesign --verify --deep --strict --verbose=4 "$(APP)"
	file "$(APP)/Contents/MacOS/3FDragUnstuck"

release:
	./scripts/package-release.sh

clean:
	rm -rf build dist
