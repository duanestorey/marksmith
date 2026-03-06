.PHONY: setup generate build run clean help

# Default target
help:
	@echo "Marksmith - macOS Markdown Editor"
	@echo ""
	@echo "Usage:"
	@echo "  make setup      Install dependencies via Homebrew"
	@echo "  make generate   Generate Xcode project from project.yml"
	@echo "  make build      Build the app (Release)"
	@echo "  make debug      Build the app (Debug)"
	@echo "  make run        Build and run the app"
	@echo "  make open       Open the project in Xcode"
	@echo "  make clean      Clean build artifacts"
	@echo "  make all        Setup, generate, and build"
	@echo ""

# Install dependencies
setup:
	@echo "Installing dependencies..."
	brew install xcodegen
	@echo "Done! Run 'make generate' next."

# Generate Xcode project
generate:
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "Done! Run 'make build' or 'make open' next."

# Build release
build: generate
	xcodebuild -project Marksmith.xcodeproj \
		-scheme Marksmith \
		-configuration Release \
		-derivedDataPath build \
		build

# Build debug
debug: generate
	xcodebuild -project Marksmith.xcodeproj \
		-scheme Marksmith \
		-configuration Debug \
		-derivedDataPath build \
		build

# Build and run
run: debug
	@echo "Launching Marksmith..."
	open build/Build/Products/Debug/Marksmith.app

# Open in Xcode
open: generate
	open Marksmith.xcodeproj

# Clean
clean:
	rm -rf build/
	rm -rf Marksmith.xcodeproj

# Full setup
all: setup generate build
