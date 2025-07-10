#!/usr/bin/env bash
# Setup script for the TaskManager Flutter project
set -euo pipefail

echo "Starting setup for TaskManager..."

# Ensure Flutter is available
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Please install Flutter and add it to your PATH."
  exit 1
fi

echo "Installing Flutter dependencies..."
flutter pub get

echo "Analyzing code..."
flutter analyze

echo "Running tests..."
flutter test

echo "Setup complete! Ready for development."
