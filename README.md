# macOS Setup Script

Automated macOS setup script that installs Homebrew, apps, fonts, and configures system defaults.

## Quick Start

1. Copy the `macos-setup` folder to your Mac
2. Open Terminal and navigate to the folder
3. Run: `./prep.command`
4. Enter your admin password when prompted

## Files

### `prep.command`
Main executable script. Run this to set up your Mac.

### `.Brewfile`
Homebrew packages (formulae, casks, fonts). Contains brief editing instructions at the top of the file.

### `.Masfile`
Mac App Store apps. One app per line: `app_id|App Name`. Contains brief editing instructions at the top of the file.

### `.Prepfile`
macOS system defaults, Dock configuration, and default browser settings. Contains brief editing instructions at the top of the file.

### `.prep-YYYYMMDD.log`
Hidden log file with detailed output from script runs. Appends if run multiple times on the same day.

## What It Does

1. Obtains admin privileges (password stored securely)
2. Installs Homebrew (if needed)
3. Prepares Homebrew (updates, configures)
4. Installs Rosetta 2 (Apple Silicon only)
5. Installs packages from `.Brewfile`
6. Sets default browser from `.Prepfile`
7. Configures Dock from `.Prepfile`
8. Applies macOS defaults from `.Prepfile`
9. Cleans up Homebrew locks
10. Installs App Store apps from `.Masfile` (optional, requires Apple ID)

## Editing Files

Each file (`.Brewfile`, `.Masfile`, `.Prepfile`) contains brief editing instructions at the top. Open the file to see how to add/remove items.

## Requirements

- macOS (tested on macOS Sonoma+)
- Admin account
- Internet connection

## Troubleshooting

- **Script fails**: Check that `prep.command` is executable: `chmod +x prep.command`
- **Homebrew fails**: Check internet connection or install manually from https://brew.sh
- **App Store apps**: Sign in to Mac App Store first: `open -a "App Store"`
- **Dock fails**: Grant Terminal.app Full Disk Access in System Settings
- **Full log**: Check `.prep-YYYYMMDD.log` for detailed output

## Settings Scope

**Most settings are user-only** (apply only to the current user). Only 2 settings are system-wide:
- `/Volumes` folder visibility (affects all users)
- Login window hostname display (affects all users)

All other settings (Finder, Safari, Dock, screenshots, etc.) are user-specific. See `SETTINGS_SCOPE.md` for details.

## Security

Password is stored securely in a temporary file, cleared from memory immediately, and deleted on script exit.
