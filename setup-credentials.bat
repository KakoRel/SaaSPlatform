@echo off
REM Script to setup credentials safely on Windows
setlocal enabledelayedexpansion

echo 🔐 Setting up credentials for SaaS Platform
echo.

REM Check if app_constants.dart already exists
if exist "lib\core\constants\app_constants.dart" (
    echo ⚠️  app_constants.dart already exists!
    set /p OVERWRITE="Do you want to overwrite it? (y/N): "
    if /i not "!OVERWRITE!"=="y" (
        echo Aborted.
        exit /b 0
    )
)

REM Copy template
echo 📋 Copying template...
copy /Y "lib\core\constants\app_constants.dart.example" "lib\core\constants\app_constants.dart" >nul

REM Ask for Supabase credentials
echo.
echo Please enter your Supabase credentials:
echo (You can find them at: https://supabase.com/dashboard/project/_/settings/api)
echo.

set /p SUPABASE_URL="Supabase URL (e.g., https://xxxxx.supabase.co): "
set /p SUPABASE_ANON_KEY="Supabase Anon Key: "

REM Validate inputs
if "!SUPABASE_URL!"=="" (
    echo ❌ Error: Supabase URL is required!
    exit /b 1
)
if "!SUPABASE_ANON_KEY!"=="" (
    echo ❌ Error: Supabase Anon Key is required!
    exit /b 1
)

REM Update the file using PowerShell
echo ✏️  Updating credentials...
powershell -Command "(Get-Content 'lib\core\constants\app_constants.dart') -replace 'YOUR_SUPABASE_URL', '!SUPABASE_URL!' | Set-Content 'lib\core\constants\app_constants.dart'"
powershell -Command "(Get-Content 'lib\core\constants\app_constants.dart') -replace 'YOUR_SUPABASE_ANON_KEY', '!SUPABASE_ANON_KEY!' | Set-Content 'lib\core\constants\app_constants.dart'"

echo.
echo ✅ Credentials configured successfully!
echo.
echo ⚠️  IMPORTANT:
echo    - app_constants.dart is in .gitignore and will NOT be committed
echo    - Never share your Supabase credentials publicly
echo    - Keep your .env files secure
echo.
echo You can now run: flutter run -d chrome
pause
