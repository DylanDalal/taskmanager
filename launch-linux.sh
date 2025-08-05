#!/usr/bin/env bash
# Launch script for running TaskManager on Linux for testing.
set -euo pipefail

echo "Setting up TaskManager for Linux testing..."

# Install Flutter if it's not already available
FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Installing to $FLUTTER_DIR..."
  git clone --quiet --depth 1 https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
  export PATH="$FLUTTER_DIR/bin:$PATH"
else
  echo "Flutter SDK found at $(command -v flutter)"
fi

echo "Checking Flutter installation..."
flutter --version

echo "Fetching dependencies..."
flutter pub get

echo "Running tests..."
flutter test

echo "Launching application..."
flutter run -d linux
