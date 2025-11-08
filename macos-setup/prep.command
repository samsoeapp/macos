#!/usr/bin/env bash

###############################################################################
# macOS bootstrap script for Crafture                                         #
#                                                                             #
# This script installs Homebrew, Rosetta (on Apple Silicon), a curated list   #
# of apps, fonts, and App Store software, and it applies a set of macOS and   #
# Finder defaults. Whenever you hit an issue the inline comments describe     #
# what to adjust to get things working again.                                 #
#                                                                             #
# Configuration is loaded from prep.config (or prep.conf) - edit that file to customize.  #
###############################################################################

# Remove -e to allow script to continue on errors
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"

# Check if script is being run with sudo (should not be)
if [[ $EUID -eq 0 ]]; then
  echo "Error: Do not run this script with sudo. Run it as a regular user:" >&2
  echo "  ./prep.command" >&2
  echo "The script will prompt for your password when needed." >&2
  exit 1
fi

# Load Dock and Default Browser config from .Prepfile (only config vars, not commands)
PREPFILE="${SCRIPT_DIR}/.Prepfile"
if [[ -f "$PREPFILE" ]]; then
  # Parse .Prepfile to extract only configuration variables
  # Stop parsing when we hit the "macOS System Defaults" section (commands start there)
  config_buffer=""
  in_dock_section=false
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Stop at the macOS System Defaults section (that's where commands start)
    if [[ "$line" =~ "macOS System Defaults" ]]; then
      break
    fi
    
    # Track if we're in Dock Configuration section
    if [[ "$line" =~ "Dock Configuration" ]]; then
      in_dock_section=true
      continue
    fi
    
    # Collect variable assignments and array contents
    if [[ "$line" =~ ^[[:space:]]*DOCK_ITEMS= ]] || \
       [[ "$line" =~ ^[[:space:]]*DEFAULT_BROWSER= ]] || \
       [[ "$in_dock_section" == "true" && "$line" =~ ^[[:space:]]*\" ]] || \
       [[ "$in_dock_section" == "true" && "$line" =~ ^[[:space:]]*\) ]]; then
      config_buffer+="$line"$'\n'
      if [[ "$line" =~ ^[[:space:]]*\) ]]; then
        in_dock_section=false
      fi
    fi
  done < "$PREPFILE"
  
  # Evaluate the config buffer to set variables (safely)
  if [[ -n "$config_buffer" ]]; then
    eval "$config_buffer" 2>/dev/null || true
  fi
  
  # Set defaults if not found
  if [[ -z "${DOCK_ITEMS:-}" ]]; then
    DOCK_ITEMS=()
  fi
  DEFAULT_BROWSER="${DEFAULT_BROWSER:-Google Chrome}"
else
  echo "Error: .Prepfile not found at $PREPFILE" >&2
  exit 1
fi

# Uncomment for very noisy output useful while debugging the script.
# set -x

# Track failures for summary at the end
FAILURES=()
SUCCESSES=()
CURRENT_STEP=""
STEP_NUM=0
TOTAL_STEPS=11

# Setup log file (create it early so all functions can use it)
# Log file appends if run multiple times on the same day
LOG_FILE="${SCRIPT_DIR}/.prep-$(date '+%Y%m%d').log"
# Append separator if file exists (new run), otherwise create it
if [[ -f "$LOG_FILE" ]]; then
  echo "" >> "$LOG_FILE"
  echo "==========================================" >> "$LOG_FILE"
  echo "New run started at $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
  echo "==========================================" >> "$LOG_FILE"
else
  touch "$LOG_FILE"  # Create log file if it doesn't exist
fi
exec 3>&1 4>&2  # Save stdout/stderr

# Log to both terminal (friendly) and file (detailed)
log_to_file() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Friendly terminal output
log() {
  local msg="$*"
  log_to_file "$msg"
  printf "\r\033[K✓ %s\n" "$msg" >&3
}

# Detailed log (only to file, not terminal)
log_detail() {
  log_to_file "$*"
}

# Warning (friendly terminal + detailed file)
warn() {
  local msg="$*"
  log_to_file "WARN: $msg"
  printf "\r\033[K⚠  %s\n" "$msg" >&3
}

# Error (friendly terminal + detailed file)
error() {
  local error_msg="$1"
  log_to_file "ERROR: $error_msg"
  printf "\r\033[K✗ %s\n" "$error_msg" >&3
  FAILURES+=("$error_msg")
}

# Step header (friendly)
step_start() {
  STEP_NUM=$((STEP_NUM + 1))
  CURRENT_STEP="$1"
  local step_msg="Step $STEP_NUM/$TOTAL_STEPS: $CURRENT_STEP"
  log_to_file "=========================================="
  log_to_file "STEP $STEP_NUM: $CURRENT_STEP"
  log_to_file "=========================================="
  printf "\n\033[1m[%d/%d]\033[0m %s...\n" "$STEP_NUM" "$TOTAL_STEPS" "$CURRENT_STEP" >&3
}

# Step success
step_success() {
  local msg="${1:-$CURRENT_STEP completed}"
  SUCCESSES+=("$msg")
  log_to_file "SUCCESS: $msg"
  printf "\r\033[K  ✓ %s\n" "$msg" >&3
}

# Step in progress
step_progress() {
  local msg="$*"
  log_to_file "PROGRESS: $msg"
  printf "\r\033[K  → %s" "$msg" >&3
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command: $1 - Install it manually and re-run the script."
    return 1
  fi
}

check_apple_id_login() {
  # Check if mas is installed first
  if ! command -v mas >/dev/null 2>&1; then
    return 0  # mas not installed yet, check will happen later
  fi
  
  if mas account >/dev/null 2>&1; then
    local apple_id
    apple_id=$(mas account 2>/dev/null)
    log_detail "Apple ID signed in: $apple_id (App Store apps will be installed)"
    return 0
  else
    # Not signed in - this is fine, App Store apps are optional
    log_detail "Apple ID not signed in - App Store apps will be skipped (optional)"
    return 1
  fi
}

keep_sudo_alive() {
  step_progress "Requesting admin password..."
  log_detail "Requesting sudo privileges (you will be prompted for your password once)..."
  
  # Prompt for password once and store it securely
  # We'll use SUDO_ASKPASS to automate password entry
  local sudo_password
  echo -n "Enter your admin password: "
  read -rs sudo_password
  echo ""  # New line after password input
  
  if [[ -z "$sudo_password" ]]; then
    error "Password cannot be empty."
    return 1
  fi
  
  # Create a temporary askpass helper script
  # This script will be used by sudo to get the password automatically
  local askpass_script
  askpass_script=$(mktemp -t sudo_askpass.XXXXXX)
  chmod 700 "$askpass_script"  # Restrict permissions to owner only
  
  # Write the password to the helper script
  cat > "$askpass_script" <<EOF
#!/bin/bash
echo "$sudo_password"
EOF
  
  # Clear password from memory immediately
  sudo_password=""
  unset sudo_password
  
  # Set SUDO_ASKPASS environment variable
  export SUDO_ASKPASS="$askpass_script"
  
  # Test sudo access with the stored password
  if ! sudo -A -v 2>/dev/null; then
    rm -f "$askpass_script"
    unset SUDO_ASKPASS
    error "Failed to obtain sudo privileges. Password may be incorrect."
    return 1
  fi
  
  # Keep sudo alive until the script ends by refreshing credentials every 2 seconds
  # Use sudo -A to use our askpass helper
  (
    set +e
    while true; do
      sleep 2
      # Refresh sudo timestamp using askpass helper
      sudo -A -v >/dev/null 2>&1 || true
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
  export SUDO_KEEPALIVE_PID
  
  # Store the askpass script path for cleanup validation
  export SUDO_ASKPASS_SCRIPT="$askpass_script"
  
  # Cleanup function to remove askpass script and clear environment
  cleanup_sudo_password() {
    local cleaned=0
    if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
      # Overwrite the file with random data before deleting (security best practice)
      if command -v shred >/dev/null 2>&1; then
        shred -u "$SUDO_ASKPASS" 2>/dev/null || rm -f "$SUDO_ASKPASS"
      else
        # Fallback: overwrite with zeros then delete
        dd if=/dev/zero of="$SUDO_ASKPASS" bs=1 count=1024 2>/dev/null || true
        rm -f "$SUDO_ASKPASS"
      fi
      cleaned=1
    fi
    # Also check the stored path
    if [[ -n "${SUDO_ASKPASS_SCRIPT:-}" ]] && [[ -f "$SUDO_ASKPASS_SCRIPT" ]]; then
      if command -v shred >/dev/null 2>&1; then
        shred -u "$SUDO_ASKPASS_SCRIPT" 2>/dev/null || rm -f "$SUDO_ASKPASS_SCRIPT"
      else
        dd if=/dev/zero of="$SUDO_ASKPASS_SCRIPT" bs=1 count=1024 2>/dev/null || true
        rm -f "$SUDO_ASKPASS_SCRIPT"
      fi
      cleaned=1
    fi
    unset SUDO_ASKPASS
    unset SUDO_ASKPASS_SCRIPT
    kill ${SUDO_KEEPALIVE_PID} >/dev/null 2>&1 || true
    
    # Log cleanup status
    if [[ $cleaned -eq 1 ]]; then
      log_detail "Password storage cleaned up securely."
    fi
  }
  
  # Register cleanup on script exit
  trap cleanup_sudo_password EXIT
  
  # Verify the background process started successfully
  sleep 0.5
  if ! kill -0 ${SUDO_KEEPALIVE_PID} 2>/dev/null; then
    warn "Sudo keep-alive background process failed to start."
    cleanup_sudo_password
    return 1
  fi
  
  # Do an immediate refresh to ensure credentials are fresh
  sudo -A -v >/dev/null 2>&1 || true
  
  log_detail "Sudo credentials cached. Password stored securely and will be deleted when script completes."
  log_detail "Keep-alive process running (PID: ${SUDO_KEEPALIVE_PID})."
}

refresh_sudo_if_needed() {
  # If SUDO_ASKPASS is set, use it for automatic password entry
  if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
    # Use askpass helper for automatic password entry
    if sudo -A -v 2>/dev/null; then
      return 0
    fi
  fi
  
  # Fallback: Try non-interactive refresh first (silent, no prompt if credentials valid)
  if sudo -n -v 2>/dev/null; then
    # Credentials are still valid
    return 0
  fi
  
  # Credentials expired or invalid - refresh interactively
  # This will prompt for password if needed
  # macOS may invalidate credentials when system processes restart (Finder/Dock)
  if sudo -v; then
    # Successfully refreshed (may have prompted for password)
    return 0
  fi
  
  # If refresh failed completely, show error
  error "Failed to refresh sudo credentials. You may need to re-run the script."
  return 1
}

ensure_homebrew() {
  # Check if Homebrew is already available
  if command -v brew >/dev/null 2>&1; then
    log_detail "Homebrew is already installed."
    configure_brew_shellenv || return 1
    return 0
  fi

  step_progress "Downloading and installing Homebrew (this may take a few minutes)..."
  log_detail "Installing Homebrew (this takes a minute and might prompt for your password)."
  # Redirect Homebrew installer output to log file only (suppress terminal output)
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1 || {
    error "Homebrew installation failed. Check the log file for details."
    return 1
  }
  configure_brew_shellenv || return 1
}

configure_brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    error "Homebrew binary not found after install. Check the installer output."
    return 1
  fi
}

prepare_brew() {
  # Ensure shellenv is configured first
  if ! command -v brew >/dev/null 2>&1; then
    configure_brew_shellenv || {
      error "Failed to configure Homebrew shellenv."
      return 1
    }
  fi
  
  # Verify brew is now available
  if ! command -v brew >/dev/null 2>&1; then
    error "Homebrew is not available even after configuring shellenv."
    return 1
  fi
  
  step_progress "Updating Homebrew..."
  log_detail "Updating Homebrew."
  # Redirect brew update output to log file only
  brew update >> "$LOG_FILE" 2>&1 || {
    warn "Failed to update Homebrew. Check your network connection."
    return 1
  }
}

install_rosetta_if_needed() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    log_detail "Skipping Rosetta 2 (Intel/AMD Mac detected)."
    return
  fi

  if /usr/bin/pgrep -q oahd; then
    log_detail "Rosetta 2 already installed."
    return
  fi

  step_progress "Installing Rosetta 2..."
  log_detail "Installing Rosetta 2 (required for Intel-only apps)."
  # Refresh sudo credentials before running sudo command
  refresh_sudo_if_needed || return 1
  # NOTE: --agree-to-license flag auto-accepts the license agreement
  # No GUI interaction needed for Rosetta installation
  # Redirect output to log file only
  if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
    sudo -A softwareupdate --install-rosetta --agree-to-license >> "$LOG_FILE" 2>&1 || {
      error "Rosetta installation failed. Check the log file for details."
      return 1
    }
  else
    sudo softwareupdate --install-rosetta --agree-to-license >> "$LOG_FILE" 2>&1 || {
      error "Rosetta installation failed. Check the log file for details."
      return 1
    }
  fi
}


install_mas_first() {
  # Install mas first since we need it for Apple ID login check
  if brew list --formula mas >/dev/null 2>&1; then
    log_detail "Formula 'mas' already installed."
    return 0
  fi
  step_progress "Installing mas (Mac App Store CLI)..."
  log_detail "Installing brew formula: mas (needed for Apple ID check)"
  # Redirect brew install output to log file only
  brew install mas >> "$LOG_FILE" 2>&1 || {
    error "Failed to install mas. Check the log file for details."
    return 1
  }
}

install_from_brewfile() {
  local brewfile_path="${SCRIPT_DIR}/.Brewfile"
  if [[ ! -f "$brewfile_path" ]]; then
    error ".Brewfile not found at $brewfile_path"
    return 1
  fi
  
  step_progress "Installing packages (this may take several minutes)..."
  log_detail "Installing packages from .Brewfile: $brewfile_path"
  # Redirect brew bundle output to log file only (not terminal)
  if ! brew bundle --file="$brewfile_path" >> "$LOG_FILE" 2>&1; then
    error "Some packages from .Brewfile failed to install. Check the log file for details."
    return 1
  fi
  log_detail "All packages from .Brewfile installed successfully."
}

install_mas_apps() {
  local masfile_path="${SCRIPT_DIR}/.Masfile"
  if [[ ! -f "$masfile_path" ]]; then
    warn ".Masfile not found at $masfile_path - skipping App Store apps"
    return 0
  fi
  
  if ! mas account >/dev/null 2>&1; then
    log "Skipping Mac App Store installs (not signed in - this is optional)"
    return 0
  fi
  
  # Read .Masfile and install apps
  local installed_ids
  if ! installed_ids=$(mas list 2>/dev/null | awk '{print $1}'); then
    error "Failed to list installed Mac App Store apps."
    return 1
  fi
  
  while IFS='|' read -r app_id app_name || [[ -n "$app_id" ]]; do
    # Skip empty lines and comments
    [[ -z "$app_id" ]] && continue
    [[ "$app_id" =~ ^[[:space:]]*# ]] && continue
    # Trim whitespace
    app_id=$(echo "$app_id" | xargs)
    app_name=$(echo "${app_name:-}" | xargs)
    
    if printf '%s\n' "$installed_ids" | grep -qx "$app_id"; then
      log_detail "App Store app '$app_name' already installed."
      continue
    fi
    step_progress "Installing ${app_name:-$app_id}..."
    log_detail "Installing App Store app: ${app_name:-$app_id} ($app_id)"
    # Redirect mas install output to log file only
    if ! mas install "$app_id" >> "$LOG_FILE" 2>&1; then
      error "mas failed for ${app_name:-$app_id} ($app_id). Check the log file for details."
    fi
  done < "$masfile_path"
}

make_default_browser() {
  local browser="${DEFAULT_BROWSER:-Google Chrome}"
  
  # Skip if no default browser is configured
  if [[ -z "$browser" ]]; then
    log_detail "No default browser configured. Skipping."
    return 0
  fi
  
  # NOTE: macOS may show a system dialog asking to confirm default browser change
  # This is a GUI notification that requires user interaction
  # The dialog will appear even if this command succeeds
  step_progress "Setting default browser..."
  log_detail "Setting $browser as default browser..."
  if ! open -a "$browser" --new --args --make-default-browser 2>/dev/null; then
    error "Failed to set $browser as default browser. macOS Sonoma and later sometimes block this flag; set it manually in the browser's settings."
  else
    log_detail "Attempted to set $browser as default browser."
    log_detail "If a system dialog appears, click 'Use $browser' to confirm."
  fi
}

configure_dock() {
  step_progress "Configuring Dock..."
  log_detail "Configuring Dock layout via dockutil."
  if ! command -v dockutil >/dev/null 2>&1; then
    error "dockutil missing even after brew install. Run 'brew install dockutil' manually."
    return 1
  fi

  # Check if DOCK_ITEMS is defined in config
  if [[ -z "${DOCK_ITEMS:-}" ]] || [[ ${#DOCK_ITEMS[@]} -eq 0 ]]; then
    warn "No dock items configured in config file. Skipping dock configuration."
    return 0
  fi

  # NOTE: dockutil may require Full Disk Access permission
  # If it fails, grant Terminal.app Full Disk Access in System Settings > Privacy & Security
  # Redirect dockutil output to log file only
  dockutil --remove all --no-restart >> "$LOG_FILE" 2>&1 || {
    error "Could not clear Dock; you may need to grant Full Disk Access to Terminal."
    return 1
  }

  for item in "${DOCK_ITEMS[@]}"; do
    if [[ "$item" == "SPACER" ]]; then
      # Add spacer tile
      dockutil --add '' --type spacer --no-restart >> "$LOG_FILE" 2>&1 || {
        error "Failed to add spacer to the Dock."
      }
    elif [[ -e "$item" ]]; then
      dockutil --add "$item" --no-restart >> "$LOG_FILE" 2>&1 || {
        error "Failed to add $item to the Dock."
      }
    else
      warn "Dock item not found: $item (install the app first, then run 'dockutil --add \"$item\"')"
    fi
  done

  # NOTE: Dock restart is visual - you'll see the Dock refresh
  killall Dock >/dev/null 2>&1 || true
}

close_system_settings() {
  log_detail "Closing System Settings to avoid configuration conflicts."
  osascript -e 'tell application "System Preferences" to quit' 2>&1 | tee -a "$LOG_FILE" >/dev/null || true
  osascript -e 'tell application "System Settings" to quit' 2>&1 | tee -a "$LOG_FILE" >/dev/null || true
}

apply_system_defaults() {
  step_progress "Applying system defaults..."
  log_detail "Applying Finder, Safari, and system defaults."
  
  local prepfile="${SCRIPT_DIR}/.Prepfile"
  if [[ ! -f "$prepfile" ]]; then
    error ".Prepfile not found at $prepfile"
    return 1
  fi
  
  # Refresh sudo before running .Prepfile (it contains sudo commands)
  refresh_sudo_if_needed || return 1
  
  # Export SUDO_ASKPASS so .Prepfile can use it
  if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
    export SUDO_ASKPASS
  fi
  
  # CRITICAL: Verify keep-alive process is still running before executing .Prepfile
  if ! kill -0 ${SUDO_KEEPALIVE_PID:-0} 2>/dev/null; then
    warn "Sudo keep-alive process stopped before .Prepfile execution. Restarting..."
    (
      set +e
      while true; do
        sleep 2
        if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
          sudo -A -v >/dev/null 2>&1 || true
        else
          sudo -v >/dev/null 2>&1 || true
        fi
      done
    ) &
    SUDO_KEEPALIVE_PID=$!
    sleep 0.5
    if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
      sudo -A -v >/dev/null 2>&1 || true
    else
      sudo -v >/dev/null 2>&1 || true
    fi
  fi
  
  # Source .Prepfile to apply macOS defaults
  # We temporarily disable -e so it continues on errors (some defaults may fail)
  set +e
  source "$prepfile" 2>&1 | while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      echo "$line" >&2
    fi
  done
  local prepfile_exit=${PIPESTATUS[0]}
  set -e
  
  # Verify keep-alive process is still running after .Prepfile execution
  if ! kill -0 ${SUDO_KEEPALIVE_PID:-0} 2>/dev/null; then
    warn "Sudo keep-alive process stopped during .Prepfile execution. Restarting..."
    (
      set +e
      while true; do
        sleep 2
        if [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -f "$SUDO_ASKPASS" ]]; then
          sudo -A -v >/dev/null 2>&1 || true
        else
          sudo -v >/dev/null 2>&1 || true
        fi
      done
    ) &
    SUDO_KEEPALIVE_PID=$!
  fi
  
  # CRITICAL: Refresh sudo credentials immediately after .Prepfile completes
  log_detail "Refreshing sudo credentials after system changes..."
  if ! refresh_sudo_if_needed; then
    warn "Sudo credentials expired after system restarts (this is normal)."
  fi
  
  if [[ $prepfile_exit -ne 0 ]]; then
    error "Some macOS defaults failed to apply. Check .Prepfile output above."
    return 1
  fi
}

cleanup_homebrew_locks() {
  log_detail "Making sure no stale Homebrew locks remain."
  
  # Ensure brew is available
  if ! command -v brew >/dev/null 2>&1; then
    configure_brew_shellenv 2>/dev/null || true
  fi
  
  # Try to get brew prefix
  local brew_prefix
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || echo "")"
  else
    # Fallback: check standard locations
    if [[ -x /opt/homebrew/bin/brew ]]; then
      brew_prefix="/opt/homebrew"
    elif [[ -x /usr/local/bin/brew ]]; then
      brew_prefix="/usr/local"
    else
      warn "Homebrew not found. Skipping lock cleanup."
      return 0  # Not an error - just skip if Homebrew isn't installed
    fi
  fi
  
  if [[ -n "$brew_prefix" ]] && [[ -d "${brew_prefix}/var/homebrew/locks" ]]; then
    rm -rf "${brew_prefix}/var/homebrew/locks" 2>/dev/null || true
    log_detail "Homebrew locks cleaned up."
  else
    log_detail "No Homebrew locks found (or Homebrew not installed)."
  fi
}

main() {
  # Redirect stdout/stderr to log file while keeping friendly output on terminal
  exec 1>&3 2>&4
  
  printf "\n\033[1m═══════════════════════════════════════════════════════════════\033[0m\n"
  printf "\033[1m  macOS Setup Script\033[0m\n"
  printf "\033[1m═══════════════════════════════════════════════════════════════\033[0m\n\n"
  log_to_file "=========================================="
  log_to_file "macOS Setup Script Started"
  log_to_file "Log file: $LOG_FILE"
  log_to_file "=========================================="
  
  printf "📝 Full log saved to: \033[2m%s\033[0m\n\n" "$LOG_FILE"
  
  require_command curl || {
    error "curl is required but not found. Please install curl and re-run the script."
    show_failures_summary
    exit 1
  }

  # Step 1: Get admin privileges
  step_start "Obtaining admin privileges"
  if keep_sudo_alive; then
    step_success "Admin privileges obtained"
  else
    warn "Could not cache sudo credentials. Some operations may prompt for password multiple times."
  fi
  
  # Step 2: Install Homebrew
  step_start "Installing/Checking Homebrew"
  if ensure_homebrew; then
    step_success "Homebrew ready"
  else
    error "Homebrew installation/configuration failed."
  fi
  
  # Step 3: Prepare Homebrew
  step_start "Preparing Homebrew"
  if prepare_brew; then
    step_success "Homebrew updated"
  else
    error "Homebrew preparation failed."
  fi
  
  # Step 4: Install Rosetta
  step_start "Installing Rosetta 2 (if needed)"
  if install_rosetta_if_needed; then
    step_success "Rosetta 2 ready"
  else
    error "Rosetta installation failed."
  fi
  
  # Step 5: Install packages
  step_start "Installing packages from .Brewfile"
  if install_from_brewfile; then
    step_success "Packages installed"
  else
    error "Package installation had errors."
  fi
  
  # Step 6: Configure default browser
  step_start "Setting default browser"
  if make_default_browser; then
    step_success "Default browser configured"
  else
    error "Default browser setup failed."
  fi
  
  # Step 7: Configure Dock
  step_start "Configuring Dock"
  if configure_dock; then
    step_success "Dock configured"
  else
    error "Dock configuration had errors."
  fi
  
  # Step 8: Close System Settings
  step_start "Closing System Settings"
  if close_system_settings; then
    step_success "System Settings closed"
  else
    warn "Failed to close system settings (may already be closed)"
  fi
  
  # Step 9: Apply system defaults
  step_start "Applying system defaults"
  refresh_sudo_if_needed || {
    error "Sudo credentials expired. Please re-run the script."
    return 1
  }
  if apply_system_defaults; then
    step_success "System defaults applied"
  else
    error "System defaults application had errors."
  fi
  
  # Step 10: Cleanup
  step_start "Cleaning up"
  if cleanup_homebrew_locks; then
    step_success "Cleanup completed"
  else
    warn "Homebrew lock cleanup had issues (non-critical)"
  fi
  
  # Step 11: Install App Store apps
  step_start "Installing Mac App Store apps (optional)"
  install_mas_first || warn "mas installation failed - skipping App Store apps"
  if mas account >/dev/null 2>&1; then
    if install_mas_apps; then
      step_success "App Store apps installed"
    else
      warn "Some App Store apps failed to install"
    fi
  else
    warn "Apple ID not signed in - App Store apps skipped"
    log_detail "To install App Store apps: sign in via App Store app, then re-run this script"
  fi

  printf "\n"
  show_failures_summary
}

show_failures_summary() {
  printf "\n\033[1m═══════════════════════════════════════════════════════════════\033[0m\n"
  printf "\033[1m  Summary\033[0m\n"
  printf "\033[1m═══════════════════════════════════════════════════════════════\033[0m\n\n"
  
  log_to_file "=========================================="
  log_to_file "SUMMARY"
  log_to_file "=========================================="
  
  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    printf "\033[32m✓ All tasks completed successfully!\033[0m\n\n"
    printf "Next steps:\n"
    printf "  • Restart your Mac to apply all changes\n"
    printf "  • Check for any GUI notifications that need your attention\n"
    printf "  • Review the full log: \033[2m%s\033[0m\n" "$LOG_FILE"
    log_to_file "SUCCESS: All tasks completed"
  else
    printf "\033[33m⚠  Completed with %d issue(s)\033[0m\n\n" "${#FAILURES[@]}"
    printf "Issues encountered:\n"
    for failure in "${FAILURES[@]}"; do
      printf "  \033[31m✗\033[0m %s\n" "$failure"
      log_to_file "FAILURE: $failure"
    done
    printf "\nWhat to do:\n"
    printf "  • Review the errors above\n"
    printf "  • Check the full log for details: \033[2m%s\033[0m\n" "$LOG_FILE"
    printf "  • Fix any issues and re-run the script if needed\n"
    log_to_file "FAILURES: ${#FAILURES[@]} issue(s) encountered"
  fi
  
  printf "\n\033[2mNote: Some operations may require manual attention:\033[0m\n"
  printf "  • App installation confirmations\n"
  printf "  • Default browser change confirmation\n"
  printf "  • Accessibility permissions\n"
  printf "  • Full Disk Access requests\n"
  
  printf "\n\033[1m═══════════════════════════════════════════════════════════════\033[0m\n"
  log_to_file "Script completed at $(date '+%Y-%m-%d %H:%M:%S')"
}

main "$@"
