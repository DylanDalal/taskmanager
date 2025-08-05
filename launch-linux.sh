#!/usr/bin/env bash
# Launch script for running TaskManager on Linux for testing.
set -euo pipefail

echo "Setting up TaskManager for Linux testing..."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Please install Flutter and add it to your PATH."
  exit 1
fi

echo "Fetching dependencies..."
flutter pub get

echo "Running tests..."
flutter test

echo "Launching application..."
flutter run -d linux

