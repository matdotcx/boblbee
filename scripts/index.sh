#########################################################
# Title; index
# Description; Call and install each module
# Source; https://github.com/matdotcx/
#########################################################

# Note: Some scripts require sudo privileges.
# They will ask for password when needed.

# Function to run script with error checking
run_script() {
    local script="$1"
    local use_sudo="$2"
    
    if [ ! -f "$script" ]; then
        echo "Error: Script $script not found"
        exit 1
    fi
    
    echo "Running $script..."
    if [ "$use_sudo" = "sudo" ]; then
        if ! sudo bash "$script"; then
            echo "Error: $script failed"
            exit 1
        fi
    else
        if ! bash "$script"; then
            echo "Error: $script failed"
            exit 1
        fi
    fi
    sleep 3
}

# Run each program
echo "Starting boblbee setup..."

run_script "touchid-sudo.sh" "sudo"
run_script "xcode.sh"
run_script "macports.sh" "sudo"
run_script "dots.sh"
run_script "claude.sh"
run_script "zshrc-sync.sh"
run_script "motd-sync.sh"
run_script "ssh-sync.sh"
