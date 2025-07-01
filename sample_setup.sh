#!/bin/bash

# Sample Development Project Setup Script
echo "🚀 Setting up development environment..."

# Check if we're in a git repository
if [ -d ".git" ]; then
    echo "✅ Git repository detected"
    echo "📍 Current branch: $(git branch --show-current)"
else
    echo "❌ Not in a git repository"
fi

# Install dependencies if package.json exists
if [ -f "package.json" ]; then
    echo "📦 Installing Node.js dependencies..."
    npm install
fi

# Install Flutter dependencies if pubspec.yaml exists
if [ -f "pubspec.yaml" ]; then
    echo "📱 Installing Flutter dependencies..."
    flutter pub get
fi

# Install Python dependencies if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "🐍 Installing Python dependencies..."
    pip install -r requirements.txt
fi

# Create common development directories
mkdir -p logs
mkdir -p temp
mkdir -p build

echo "✨ Setup complete! Ready for development."
echo "📝 Don't forget to:"
echo "   - Configure your IDE settings"
echo "   - Set up environment variables"
echo "   - Review the project README" 