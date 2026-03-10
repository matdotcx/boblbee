#!/bin/zsh

#########################################################
# Title; defaults
# Description; "Sane" (oppinionated) dots and defaults
#               for macOS usability.
# Source; https://github.com/matdotcx/boblbee/
# Edition: Tue 17 Sep 2024 20:41:26 BST
#########################################################

# Set up logging
LOG_FILE=~/boblbee.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting macOS setup script at $(date)"

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Get current Username and User ID
CURRENT_USER=$(stat -f %Su /dev/console)
USER_ID=$(id -u "$CURRENT_USER")

echo "Current user: $CURRENT_USER (ID: $USER_ID)"

#########################################################
# User-Configurable Variables
#########################################################

# Get current computer name
current_name=$(scutil --get ComputerName 2>/dev/null || echo "Unknown")

# Prompt for computer name
echo "Current computer name: $current_name"
read -p "Enter new computer name (or press Enter to keep current): " input_name

if [[ -n "$input_name" ]]; then
    # Validate input (no spaces or special characters for hostname compatibility)
    if [[ "$input_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        COMPUTER_NAME="$input_name"
    else
        echo "Invalid name. Using current name: $current_name"
        COMPUTER_NAME="$current_name"
    fi
else
    COMPUTER_NAME="$current_name"
fi

MACOS_UI_COLOR="orange" # Set your desired UI color here

echo "Computer name set to: $COMPUTER_NAME"
echo "UI color set to: $MACOS_UI_COLOR"

#########################################################
# Color Definitions
#########################################################

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

#########################################################
# Helper Functions
#########################################################

run_command() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running: $1"
    if eval "$1"; then
        echo -e "${GREEN}[OK]${NC} Success: $2"
    else
        echo -e "${RED}[ERROR]${NC} Failed: $2"
    fi
}

is_portable() {
    if system_profiler SPHardwareDataType 2>/dev/null | grep -q "MacBook"; then
        echo "Machine type: Portable"
        return 0
    else
        echo "Machine type: Desktop"
        return 1
    fi
}

get_macos_color_values() {
    local color=${1:-$MACOS_UI_COLOR}

    local -A ACCENT_COLORS=(
        [blue]=4 [purple]=5 [pink]=6 [red]=0 [orange]=1 [yellow]=2 [green]=3 [graphite]=-1
    )
    local -A HIGHLIGHT_COLORS=(
        [blue]="0.698039 0.843137 1.000000 Blue"
        [purple]="0.968627 0.831373 1.000000 Purple"
        [pink]="1.000000 0.749020 0.823529 Pink"
        [red]="1.000000 0.733333 0.721569 Red"
        [orange]="1.000000 0.874510 0.701961 Orange"
        [yellow]="1.000000 0.937255 0.690196 Yellow"
        [green]="0.752941 0.964706 0.678431 Green"
        [graphite]="0.847059 0.847059 0.862745 Graphite"
    )

    if [[ -n "${ACCENT_COLORS[$color]}" ]]; then
        accent_color=${ACCENT_COLORS[$color]}
        highlight_color="${HIGHLIGHT_COLORS[$color]}"
        echo "Color values set for $color"
        return 0
    else
        echo "Invalid color specified. Valid colors are: ${(k)ACCENT_COLORS}" >&2
        return 1
    fi
}

#########################################################
# System Configuration
#########################################################

echo "Configuring system settings…"

echo ""
echo "Setting computer name…"
run_command "sudo scutil --set ComputerName '$COMPUTER_NAME'" "Set computer name"
run_command "sudo scutil --set HostName '$COMPUTER_NAME'" "Set host name"
run_command "sudo scutil --set LocalHostName '$COMPUTER_NAME'" "Set local host name"
run_command "sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string '$COMPUTER_NAME'" "Set NetBIOS name"

echo ""
echo "Setting macOS UI color…"
if get_macos_color_values; then
    run_command "defaults write -g AppleAccentColor -int $accent_color" "Set accent color"
    run_command "defaults write -g AppleHighlightColor -string '$highlight_color'" "Set highlight color"
    echo "UI color changes applied. A logout/login or restart is required for all changes to take effect."
else
    echo "Failed to set macOS UI color"
fi

echo ""
echo "Configuring Finder…"
run_command "/usr/libexec/PlistBuddy -c \"Set DesktopViewSettings:IconViewSettings:labelOnBottom false\" ~/Library/Preferences/com.apple.finder.plist" "Set desktop icon labels to side"
run_command "/usr/libexec/PlistBuddy -c \"Set :DesktopViewSettings:IconViewSettings:arrangeBy grid\" ~/Library/Preferences/com.apple.finder.plist" "Arrange desktop icons by grid"
run_command "/usr/libexec/PlistBuddy -c \"Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid\" ~/Library/Preferences/com.apple.finder.plist" "Arrange standard view icons by grid"
run_command "/usr/libexec/PlistBuddy -c \"Set :StandardViewSettings:IconViewSettings:arrangeBy grid\" ~/Library/Preferences/com.apple.finder.plist" "Arrange all view icons by grid"
run_command "/usr/libexec/PlistBuddy -c \"Set :DesktopViewSettings:IconViewSettings:gridSpacing 100\" ~/Library/Preferences/com.apple.finder.plist" "Set desktop icon grid spacing"
run_command "/usr/libexec/PlistBuddy -c \"Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 100\" ~/Library/Preferences/com.apple.finder.plist" "Set standard view icon grid spacing"
run_command "/usr/libexec/PlistBuddy -c \"Set :StandardViewSettings:IconViewSettings:gridSpacing 100\" ~/Library/Preferences/com.apple.finder.plist" "Set all view icon grid spacing"
run_command "/usr/libexec/PlistBuddy -c \"Set :DesktopViewSettings:IconViewSettings:iconSize 80\" ~/Library/Preferences/com.apple.finder.plist" "Set desktop icon size"
run_command "/usr/libexec/PlistBuddy -c \"Set :FK_StandardViewSettings:IconViewSettings:iconSize 80\" ~/Library/Preferences/com.apple.finder.plist" "Set standard view icon size"
run_command "/usr/libexec/PlistBuddy -c \"Set :StandardViewSettings:IconViewSettings:iconSize 80\" ~/Library/Preferences/com.apple.finder.plist" "Set all view icon size"
run_command "/usr/libexec/PlistBuddy -c \"Set :DesktopViewSettings:IconViewSettings:showItemInfo true\" ~/Library/Preferences/com.apple.finder.plist" "Show item info on desktop icons"
run_command "/usr/libexec/PlistBuddy -c \"Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true\" ~/Library/Preferences/com.apple.finder.plist" "Show item info in standard Finder views"
run_command "defaults write NSGlobalDomain AppleShowAllExtensions -bool true" "Show all file extensions"
run_command "defaults write com.apple.finder ShowPathbar -bool true" "Show Finder path bar"
run_command "defaults write com.apple.finder ShowStatusBar -bool true" "Show Finder status bar"
run_command "defaults write com.apple.finder NewWindowTarget -string \"PfHm\"" "Set new Finder windows to home folder"
run_command "defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false" "Hide hard drives on desktop"
run_command "defaults write com.apple.finder ShowMountedServersOnDesktop -bool true" "Show mounted servers on desktop"
run_command "defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true" "Show removable media on desktop"

echo ""
echo "Configuring UI/UX settings…"
run_command "defaults write com.apple.universalaccess \"showWindowTitlebarIcons\" -bool \"true\"" "Show window titlebar icons"
run_command "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true" "Expand save panel by default"
run_command "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true" "Expand save panel by default (v2)"
run_command "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true" "Expand print panel by default"
run_command "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true" "Expand print panel by default (v2)"
run_command "defaults write NSGlobalDomain com.apple.springing.enabled -bool true" "Enable spring loading for directories"
run_command "defaults write NSGlobalDomain com.apple.springing.delay -float 0" "Remove the spring loading delay for directories"
run_command "defaults write NSGlobalDomain AppleShowScrollBars -string \"Always\"" "Always show scrollbars"
run_command "defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -int 1" "Disable force click"
run_command "defaults write com.apple.AppleMultitouchMouse MouseButtonMode -string \"TwoButton\"" "Enable two-button mouse"
run_command "defaults write com.apple.driver.AppleBluetoothMultitouch.mouse MouseButtonMode -string \"TwoButton\"" "Enable two-button Bluetooth mouse"
run_command "defaults write NSGlobalDomain com.apple.sound.beep.feedback -integer 1" "Enable sound feedback"
run_command "defaults write com.apple.PowerChime ChimeOnAllHardware -bool true" "Enable power chime"
run_command "defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true" "Disable Time Machine new disk prompt"

echo ""
echo "Configuring Dock…"
run_command "defaults write com.apple.dock orientation -string right" "Set Dock to right side"
run_command "defaults write com.apple.dock mineffect -string scale" "Set Dock minimize effect to scale"
run_command "defaults write com.apple.dock tilesize -int 22" "Set Dock tile size to 22px"
run_command "defaults write com.apple.dock magnification -bool true" "Set Dock Magnifcation to on"
run_command "defaults write com.apple.dock largesize -int 96" "Set Dock tile max size to 96px"


echo ""
echo "Configuring Menu Bar…"
run_command "defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true" "Show battery percentage"
run_command "defaults write com.apple.menuextra.clock IsAnalog -int 0" "Enable digital clock"
run_command "defaults write com.apple.menuextra.clock Show24Hour -int 1" "Enable 24-hour clock"
run_command "defaults write com.apple.menuextra.clock ShowDayOfWeek -int 1" "Show day of week in clock"
run_command "defaults write com.apple.menuextra.clock ShowSeconds -int 1" "Show seconds in clock"
run_command "defaults write com.apple.menuextra.clock FlashDateSeparators -bool true" "Enable flashing clock separators"
run_command "defaults -currentHost write com.apple.controlcenter Bluetooth -int 18" "Show Bluetooth in menu bar"
run_command "defaults -currentHost write com.apple.controlcenter Sound -int 18" "Show sound in menu bar"

echo ""
echo "Configuring Safari…"
run_command "defaults write com.apple.Safari ShowFavoritesBar-v2 -bool true" "Enable Safari favorites bar"
run_command "defaults write com.apple.Safari ShowOverlayStatusBar -bool true" "Enable Safari status bar"
run_command "defaults write com.apple.Safari \"ShowFullURLInSmartSearchField\" -bool \"true\"" "Show full URL in Safari search field"

echo ""
echo "Configuring system behavior…"
run_command "defaults write com.apple.loginwindow TALLogoutSavesState -bool false" "Disable reopening windows on login"
run_command "sudo defaults write /Library/Preferences/com.apple.timezone.auto Active -bool YES" "Enable automatic timezone"
run_command "sudo defaults write /private/var/db/timed/Library/Preferences/com.apple.timed.plist TMAutomaticTimeOnlyEnabled -bool YES" "Enable automatic time"
run_command "sudo defaults write /private/var/db/timed/Library/Preferences/com.apple.timed.plist TMAutomaticTimeZoneEnabled -bool YES" "Enable automatic timezone"
run_command "sudo nvram StartupMute=%00" "Enable startup chime"

echo ""
echo "Enabling automatic updates…"
run_command "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticallyInstallMacOSUpdates -bool true" "Enable automatic macOS updates"
run_command "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled -bool true" "Enable automatic update check"
run_command "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticDownload -bool true" "Enable automatic update download"
run_command "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist CriticalUpdateInstall -bool true" "Enable critical update installation"
run_command "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool true" "Enable config data installation"
run_command "sudo defaults write /Library/Preferences/com.apple.commerce.plist AutoUpdate -bool true" "Enable App Store automatic updates"

echo ""
echo "Disabling Siri…"
run_command "defaults write com.apple.Siri StatusMenuVisible -bool false" "Hide Siri menu bar icon"
run_command "defaults write com.apple.assistant.support \"Assistant Enabled\" -bool false" "Disable Siri"

#########################################################
# Machine-Specific Settings
#########################################################

if is_portable; then
    echo ""
    echo "Applying settings for portable machines…"
    if ! sudo systemsetup -setdisplaysleep 3; then
        echo -e "${YELLOW}[WARNING]${NC} Failed to set display sleep. You may need to set this manually."
    else
        echo -e "${GREEN}[OK]${NC} Set display sleep to 3 minutes"
    fi

    if ! sudo systemsetup -setcomputersleep 10; then
        echo -e "${YELLOW}[WARNING]${NC} Failed to set computer sleep. You may need to set this manually."
    else
        echo -e "${GREEN}[OK]${NC} Set computer sleep to 10 minutes"
    fi

    run_command "sudo nvram AutoBoot=%00" "Disable AutoBoot"
else
    echo ""
    echo "Applying settings for desktop machines…"
    if ! sudo systemsetup -setdisplaysleep never; then
        echo -e "${YELLOW}[WARNING]${NC} Failed to disable display sleep. You may need to set this manually."
    else
        echo -e "${GREEN}[OK]${NC} Disabled display sleep"
    fi

    if ! sudo systemsetup -setcomputersleep never; then
        echo -e "${YELLOW}[WARNING]${NC} Failed to disable computer sleep. You may need to set this manually."
    else
        echo -e "${GREEN}[OK]${NC} Disabled computer sleep"
    fi

    run_command "sudo systemsetup -setrestartpowerfailure on" "Enable restart on power failure"
    run_command "sudo systemsetup -setwaitforstartupafterpowerfailure 30" "Set wait for startup after power failure to 30 seconds"
fi

#########################################################
# Cleanup and Finalization
#########################################################

echo ""
echo "Restarting affected applications…"
killall Finder Dock SystemUIServer
echo "Flushing DNS…"
dscacheutil -flushcache
echo "Waiting for applications to restart…"
sleep 5  # Give applications time to restart

echo ""
echo "Verifying critical settings…"
current_color=$(defaults read -g AppleAccentColor)
if [ "$current_color" != "$accent_color" ]; then
    echo -e "${YELLOW}[WARNING]${NC} Accent color may not have been set correctly."
else
    echo -e "${GREEN}[OK]${NC} Accent color verified successfully."
fi

echo ""
echo "#########################################################"
echo "Setup complete at $(date)."
echo "Please log out and log back in, or restart your Mac"
echo "to ensure all changes are applied."
echo "#########################################################"
echo ""
echo "Log file has been saved to $LOG_FILE"
