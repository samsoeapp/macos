# macOS Setup Client

Lightweight macOS setup script that installs Homebrew packages and applies
user defaults. Configuration lives inline in `prep.sh`.

## Oneliner (Admin access required for Homebrew install)
curl -fsSL https://raw.githubusercontent.com/samsoeapp/macos/refs/heads/main/macos-setup-client/prep.sh | sudo bash

## Oneliner with Client Profile
Use `--client NAME` or a positional `NAME`.

curl -fsSL https://raw.githubusercontent.com/samsoeapp/macos/refs/heads/main/macos-setup-client/prep.sh | sudo bash -s -- --client RD
curl -fsSL https://raw.githubusercontent.com/samsoeapp/macos/refs/heads/main/macos-setup-client/prep.sh | sudo bash -s -- RD

## Quick Start

1. Copy the `macos-setup-client` folder to your Mac
2. Open Terminal and navigate to the folder
3. Run: `./prep.sh`
4. Optional: `./prep.sh --client RD`

## Files

### `prep.sh`
Main executable script. All configuration is inline in this file.

### `.prep-defaults-YYYYMMDD.log`
Hidden log file written to `~/Downloads`. Appends if run multiple times on the same day.

## What It Does

1. Ensures Xcode Command Line Tools are installed
2. Installs Homebrew (if needed)
3. Installs Homebrew formulae and casks (inline lists)
4. Closes System Settings (to avoid conflicts)
5. Applies macOS defaults (or reverts with `--revert`)
6. Restarts affected apps (Safari, Finder)

## Editing Configuration

Edit `prep.sh` directly:
- Default apps: `DEFAULT_BROWSER` (and optional defaults)
- Homebrew packages: `BREW_FORMULAE`, `BREW_CASKS`
- Mac App Store apps: `MAS_APPS` (currently disabled in the script)
- macOS defaults: `apply_defaults` / `apply_defaults_revert`
- Admin-only commands: commented at the end of the file

Client profiles live in `profiles/NAME.sh` and can override or append to any of
the variables above.

## Requirements

- macOS (tested on macOS Sonoma+)
- Internet connection
- Admin account (for Homebrew install)

## Troubleshooting

- **Script fails**: Ensure executable: `chmod +x prep.sh`
- **Homebrew fails**: Check internet connection or install manually from https://brew.sh
- **App Store apps**: Uncomment the MAS section and sign in first: `open -a "App Store"`
- **Full log**: Check `~/Downloads/.prep-defaults-YYYYMMDD.log`

## Settings Scope

All defaults in `prep.sh` are user-level. Two admin-only settings are present
but commented out at the end of the file:
- `/Volumes` folder visibility
- Login window hostname display
