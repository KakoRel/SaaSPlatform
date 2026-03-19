#!/bin/bash

# Script to setup credentials safely
set -e

echo "🔐 Setting up credentials for SaaS Platform"

# Check if app_constants.dart already exists
if [ -f "lib/core/constants/app_constants.dart" ]; then
    echo "⚠️  app_constants.dart already exists!"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Copy template
echo "📋 Copying template..."
cp lib/core/constants/app_constants.dart.example lib/core/constants/app_constants.dart

# Ask for Supabase credentials
echo ""
echo "Please enter your Supabase credentials:"
echo "(You can find them at: https://supabase.com/dashboard/project/_/settings/api)"
echo ""

read -p "Supabase URL (e.g., https://xxxxx.supabase.co): " SUPABASE_URL
read -p "Supabase Anon Key: " SUPABASE_ANON_KEY

# Validate inputs
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "❌ Error: Both URL and Anon Key are required!"
    exit 1
fi

# Update the file
echo "✏️  Updating credentials..."
sed -i "s|YOUR_SUPABASE_URL|$SUPABASE_URL|g" lib/core/constants/app_constants.dart
sed -i "s|YOUR_SUPABASE_ANON_KEY|$SUPABASE_ANON_KEY|g" lib/core/constants/app_constants.dart

echo ""
echo "✅ Credentials configured successfully!"
echo ""
echo "⚠️  IMPORTANT:"
echo "   - app_constants.dart is in .gitignore and will NOT be committed"
echo "   - Never share your Supabase credentials publicly"
echo "   - Keep your .env files secure"
echo ""
echo "You can now run: flutter run -d chrome"
