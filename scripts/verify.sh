#!/bin/bash

# Quick verification script
# Run this to verify everything is working before pushing to GitHub

echo "🔍 Running Project Verification..."
echo "=================================="
echo ""

# Check if virtual environment is activated
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "⚠️  Virtual environment not activated!"
    echo "Run: source myenv/bin/activate"
    exit 1
fi

echo "✅ Virtual environment: activated"
echo ""

# Run linting
echo "📝 Running flake8 linting..."
if flake8 .; then
    echo "✅ Linting: PASSED"
else
    echo "❌ Linting: FAILED"
    exit 1
fi
echo ""

# Run tests
echo "🧪 Running tests with coverage..."
if pytest --cov=. --cov-report=term-missing -q; then
    echo "✅ Tests: PASSED"
else
    echo "❌ Tests: FAILED"
    exit 1
fi
echo ""

echo "=================================="
echo "🎉 All checks passed!"
echo "Your project is ready for deployment!"
echo ""
echo "Next steps:"
echo "1. Commit your changes: git add . && git commit -m 'Ready for deployment'"
echo "2. Follow SETUP_GUIDE.md to push to GitHub"
echo "=================================="
