#!/usr/bin/env bash
# HOW TO EDIT THIS FILE:
# - Dock items: Add/remove app paths in DOCK_ITEMS array
# - Default browser: Change DEFAULT_BROWSER value
# - macOS defaults: Edit defaults commands below (use: defaults read <domain> to see current values)
# - Homebrew packages: Add/remove entries in BREW_FORMULAE/BREW_CASKS arrays
# - App Store apps: Add/remove entries in MAS_APPS array (format: "app_id|App Name")
# - Admin-only commands are moved to the end and commented out
# After editing, run: ./prep.sh

set -u -o pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"

###############################################################################
# Dock Configuration                                                          #
###############################################################################

DOCK_ITEMS=(
  "/Applications/Google Chrome.app"
  "/Applications/Google Drive.app"
  "/Applications/1Password.app"
  "/Applications/WhatsApp.app"
  "/Applications/Slack.app"
  "/Applications/Microsoft Word.app"
  "/Applications/Microsoft Excel.app"
  "/System/Applications/Notes.app"
  "/System/Applications/Calendar.app"
  "/Applications/Safari.app"
  "/System/Applications/System Settings.app"
)

###############################################################################
# Homebrew                                                                    #
###############################################################################

BREW_FORMULAE=(
  "mas"
  "dockutil"
)

BREW_CASKS=(
  "1password"
  "slack"
  "google-chrome"
  "google-drive"
  "whatsapp"
)

###############################################################################
# Mac App Store (mas)                                                         #
###############################################################################

MAS_APPS=(
  "409201541|Pages"
  "409203825|Numbers"
  "409183694|Keynote"
)

###############################################################################
# Default Apps                                                              #
###############################################################################

DEFAULT_BROWSER="Google Chrome"

###############################################################################
# Logging and Helpers                                                         #
###############################################################################

LOG_FILE="${SCRIPT_DIR}/.prep-defaults-$(date '+%Y%m%d').log"
FAILURES=()
STEP_NUM=0
TOTAL_STEPS=4
REVERT_DEFAULTS=false

log_to_file() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

log() {
  log_to_file "$*"
  printf "[OK] %s\n" "$*"
}

warn() {
  log_to_file "WARN: $*"
  printf "[WARN] %s\n" "$*" >&2
}

error() {
  log_to_file "ERROR: $*"
  printf "[ERROR] %s\n" "$*" >&2
  FAILURES+=("$*")
}

filter_dock_items() {
  local item
  local filtered=()
  local missing=()

  for item in "${DOCK_ITEMS[@]}"; do
    if [[ "$item" == "SPACER" ]]; then
      filtered+=("$item")
    elif [[ -e "$item" ]]; then
      filtered+=("$item")
    else
      missing+=("$item")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Dock item not found, skipping:"
    for item in "${missing[@]}"; do
      warn "  - $item"
    done
  fi

  DOCK_ITEMS=("${filtered[@]}")
}

filter_dock_items

step_start() {
  STEP_NUM=$((STEP_NUM + 1))
  printf "\n[%d/%d] %s\n" "$STEP_NUM" "$TOTAL_STEPS" "$1"
  log_to_file "STEP $STEP_NUM/$TOTAL_STEPS: $1"
}

show_setting() {
  local label="$1"
  local domain="$2"
  local key="$3"
  local current="(not set)"
  if defaults read "$domain" "$key" >/dev/null 2>&1; then
    current="$(defaults read "$domain" "$key")"
  fi
  printf "%s: %s\n" "$label" "$current"
}

run_cmd() {
  local desc="$1"
  shift
  if "$@" >> "$LOG_FILE" 2>&1; then
    log "$desc"
  else
    error "$desc (failed)"
  fi
}

run_optional() {
  local desc="$1"
  shift
  if "$@" >> "$LOG_FILE" 2>&1; then
    log "$desc"
  else
    warn "$desc (failed, ignored)"
  fi
}

show_summary() {
  printf "\nSummary\n"
  printf "-------\n"
  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    printf "All tasks completed successfully.\n"
  else
    printf "Completed with %d issue(s):\n" "${#FAILURES[@]}"
    for failure in "${FAILURES[@]}"; do
      printf "  - %s\n" "$failure"
    done
  fi
  printf "Log file: %s\n" "$LOG_FILE"
}

show_usage() {
  printf "Usage: %s [--revert]\n" "$(basename "$0")"
  printf "  --revert  Revert defaults set by this script\n"
}

###############################################################################
# Homebrew                                                                    #
###############################################################################

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed"
    return 0
  fi

  if ! command -v /bin/bash >/dev/null 2>&1; then
    error "bash not available for Homebrew install"
    return 1
  fi

  run_cmd "Install Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_brew_packages() {
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not installed; skipping package install"
    return 0
  fi

  local formula
  for formula in "${BREW_FORMULAE[@]}"; do
    run_optional "Install Homebrew formula ($formula)" brew install "$formula"
  done

  local cask
  for cask in "${BREW_CASKS[@]}"; do
    run_optional "Install Homebrew cask ($cask)" brew install --cask "$cask"
  done
}

###############################################################################
# Mac App Store (mas)                                                         #
###############################################################################

install_mas_apps() {
  if ! command -v mas >/dev/null 2>&1; then
    warn "mas not installed; skipping App Store installs"
    return 0
  fi

  if [[ ${#MAS_APPS[@]} -eq 0 ]]; then
    warn "No App Store apps listed; skipping"
    return 0
  fi

  local entry app_id app_name
  for entry in "${MAS_APPS[@]}"; do
    app_id="${entry%%|*}"
    app_name="${entry#*|}"
    if [[ -z "$app_id" || "$app_id" == "$app_name" ]]; then
      warn "Skipping invalid MAS entry: $entry"
      continue
    fi
    run_optional "Install App Store app (${app_name})" mas install "$app_id"
  done
}

###############################################################################
# macOS System Defaults                                                       #
###############################################################################

close_system_settings() {
  run_optional "Close System Preferences" osascript -e 'tell application "System Preferences" to quit'
  run_optional "Close System Settings" osascript -e 'tell application "System Settings" to quit'
}

apply_defaults() {
  # General UI/UX
  run_cmd "Expand save panel (save)" defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  run_cmd "Expand save panel (save2)" defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
  run_cmd "Expand print panel (print)" defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  run_cmd "Expand print panel (print2)" defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
  run_cmd "Disable Siri status menu" defaults write com.apple.Siri SiriPrefStashedStatusMenuVisible -bool false
  run_cmd "Disable Siri voice trigger" defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false
  run_cmd "Always prefer tabs" defaults write -g AppleWindowTabbingMode -string always
  run_cmd "Show Bluetooth in Control Center" defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool true
  run_cmd "Show Sound in Control Center" defaults write com.apple.controlcenter "NSStatusItem Visible Sound" -bool true
  run_cmd "Hide Spotlight menu item" defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1

  # Finder
  run_cmd "Show Finder path bar" defaults write com.apple.finder ShowPathbar -bool true
  run_cmd "Default Finder view style (list)" defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  run_cmd "Show Finder status bar" defaults write com.apple.finder ShowStatusBar -boolean true
  run_cmd "Show hidden files" defaults write com.apple.finder AppleShowAllFiles true
  run_cmd "Show file extensions" defaults write NSGlobalDomain AppleShowAllExtensions -boolean true

  # Unhide ~/Library
  run_optional "Unhide ~/Library" chflags nohidden "$HOME/Library"
  run_optional "Remove FinderInfo xattr" xattr -d com.apple.FinderInfo "$HOME/Library"

  # Text Input
  run_cmd "Disable auto-capitalization" defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  run_cmd "Disable auto-correction" defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  # Bluetooth
  run_cmd "Set Bluetooth audio quality" defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40

  # Network
  run_cmd "Browse all network interfaces" defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true

  # Screenshots
  run_cmd "Save screenshots to Downloads" defaults write com.apple.screencapture location -string "$HOME/Downloads"
  run_cmd "Use PNG for screenshots" defaults write com.apple.screencapture type -string "png"

  # Safari (ignore failures if Safari is not present)
  run_optional "Enable Safari Develop menu" defaults write com.apple.Safari IncludeDevelopMenu -bool true
  run_optional "Enable Safari WebKit developer extras (global)" defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  run_optional "Enable Safari WebKit developer extras" defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  run_optional "Disable Safari AutoFill Address Book" defaults write com.apple.Safari AutoFillFromAddressBook -bool false
  run_optional "Disable Safari AutoFill Passwords" defaults write com.apple.Safari AutoFillPasswords -bool false
  run_optional "Disable Safari AutoFill Credit Cards" defaults write com.apple.Safari AutoFillCreditCardData -bool false
  run_optional "Disable Safari AutoFill Misc" defaults write com.apple.Safari AutoFillMiscellaneousForms -bool false
  run_optional "Enable Safari Do Not Track" defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
}

apply_defaults_revert() {
  # General UI/UX
  run_optional "Revert save panel expansion (save)" defaults delete NSGlobalDomain NSNavPanelExpandedStateForSaveMode
  run_optional "Revert save panel expansion (save2)" defaults delete NSGlobalDomain NSNavPanelExpandedStateForSaveMode2
  run_optional "Revert print panel expansion (print)" defaults delete NSGlobalDomain PMPrintingExpandedStateForPrint
  run_optional "Revert print panel expansion (print2)" defaults delete NSGlobalDomain PMPrintingExpandedStateForPrint2
  run_optional "Revert Siri status menu" defaults delete com.apple.Siri SiriPrefStashedStatusMenuVisible
  run_optional "Revert Siri voice trigger" defaults delete com.apple.Siri VoiceTriggerUserEnabled
  run_optional "Revert window tabbing preference" defaults delete -g AppleWindowTabbingMode
  run_optional "Revert Bluetooth Control Center item" defaults delete com.apple.controlcenter "NSStatusItem Visible Bluetooth"
  run_optional "Revert Sound Control Center item" defaults delete com.apple.controlcenter "NSStatusItem Visible Sound"
  run_optional "Revert Spotlight menu item" defaults -currentHost delete com.apple.Spotlight MenuItemHidden

  # Finder
  run_optional "Revert Finder path bar" defaults delete com.apple.finder ShowPathbar
  run_optional "Revert Finder view style" defaults delete com.apple.finder FXPreferredViewStyle
  run_optional "Revert Finder status bar" defaults delete com.apple.finder ShowStatusBar
  run_optional "Revert hidden files visibility" defaults delete com.apple.finder AppleShowAllFiles
  run_optional "Revert file extensions visibility" defaults delete NSGlobalDomain AppleShowAllExtensions

  # ~/Library visibility
  run_optional "Hide ~/Library" chflags hidden "$HOME/Library"

  # Text Input
  run_optional "Revert auto-capitalization" defaults delete NSGlobalDomain NSAutomaticCapitalizationEnabled
  run_optional "Revert auto-correction" defaults delete NSGlobalDomain NSAutomaticSpellingCorrectionEnabled

  # Bluetooth
  run_optional "Revert Bluetooth audio quality" defaults delete com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)"

  # Network
  run_optional "Revert network interface browsing" defaults delete com.apple.NetworkBrowser BrowseAllInterfaces

  # Screenshots
  run_optional "Revert screenshot location" defaults delete com.apple.screencapture location
  run_optional "Revert screenshot format" defaults delete com.apple.screencapture type

  # Safari (ignore failures if Safari is not present)
  run_optional "Revert Safari Develop menu" defaults delete com.apple.Safari IncludeDevelopMenu
  run_optional "Revert Safari WebKit developer extras (global)" defaults delete com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey
  run_optional "Revert Safari WebKit developer extras" defaults delete com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled
  run_optional "Revert Safari AutoFill Address Book" defaults delete com.apple.Safari AutoFillFromAddressBook
  run_optional "Revert Safari AutoFill Passwords" defaults delete com.apple.Safari AutoFillPasswords
  run_optional "Revert Safari AutoFill Credit Cards" defaults delete com.apple.Safari AutoFillCreditCardData
  run_optional "Revert Safari AutoFill Misc" defaults delete com.apple.Safari AutoFillMiscellaneousForms
  run_optional "Revert Safari Do Not Track" defaults delete com.apple.Safari SendDoNotTrackHTTPHeader
}

restart_apps() {
  run_optional "Restart Safari" killall Safari
  run_optional "Restart Finder" killall Finder
}

main() {
  for arg in "$@"; do
    case "$arg" in
      --revert)
        REVERT_DEFAULTS=true
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
    esac
  done

  printf "macOS Defaults Setup\n"
  printf "Log file: %s\n\n" "$LOG_FILE"

  printf "Summary before applying macOS defaults:\n"
  show_setting "Show all filename extensions" "NSGlobalDomain" "AppleShowAllExtensions"
  show_setting "Show Finder status bar" "com.apple.finder" "ShowStatusBar"
  show_setting "Show Finder path bar" "com.apple.finder" "ShowPathbar"
  show_setting "Default Finder view style" "com.apple.Finder" "FXPreferredViewStyle"
  printf "\n"

  step_start "Closing System Settings"
  close_system_settings

  step_start "Applying macOS defaults"
  if [[ "$REVERT_DEFAULTS" == "true" ]]; then
    apply_defaults_revert
  else
    apply_defaults
  fi

  step_start "Restarting affected apps"
  restart_apps

  # Optional: Install Mac App Store apps (requires mas + sign-in)
  # step_start "Installing App Store apps"
  # install_mas_apps

  # Optional: Install Homebrew
  step_start "Installing Homebrew"
  install_homebrew

  # Optional: Install Homebrew packages (inline list)
  step_start "Installing Homebrew packages"
  install_brew_packages

  # Optional: Reset Dock to defaults (uncomment to enable)
  # step_start "Resetting Dock to defaults"
  # run_cmd "Reset Dock to default icons" defaults delete com.apple.dock
  # run_optional "Restart Dock" killall Dock

  printf "\nSummary after applying macOS defaults:\n"
  show_setting "Show all filename extensions" "NSGlobalDomain" "AppleShowAllExtensions"
  show_setting "Show Finder status bar" "com.apple.finder" "ShowStatusBar"
  show_setting "Show Finder path bar" "com.apple.finder" "ShowPathbar"
  show_setting "Default Finder view style" "com.apple.Finder" "FXPreferredViewStyle"

  show_summary
}

main "$@"

###############################################################################
# Admin-only commands (disabled)                                              #
###############################################################################
# The commands below require admin privileges. They are intentionally commented
# out and moved to the end of the file per request. Uncomment and run manually
# if/when you want to apply them.
#
# Show /Volumes
# sudo chflags nohidden /Volumes
#
# Login Window - show host info
# sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
