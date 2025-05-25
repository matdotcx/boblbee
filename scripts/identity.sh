#!/bin/bash
#!/bin/bash

check_icloud_signin_and_create_symlinks() {
    local account_info=$(defaults read MobileMeAccounts 2>/dev/null)
    local had_errors=false

    if [[ -z "$account_info" ]]; then
        echo "No iCloud account found."
        return 1
    fi

    local apple_id=$(echo "$account_info" | grep "AccountID" | head -1 | sed 's/.*= "\(.*\)";/\1/')
    
    if [[ -n "$apple_id" ]]; then
        echo "Found iCloud account: $apple_id"
        
        # Use proper path escaping
        local icloud_path="${HOME}/Library/Mobile Documents/com~apple~CloudDocs/Ark/Sync/System"
        
        # Create symlinks and track errors
        create_symlink "${icloud_path}/.ssh" "${HOME}/.ssh" || had_errors=true
        create_symlink "${icloud_path}/.zshrc" "${HOME}/.zshrc" || had_errors=true
        
        if [ "$had_errors" = true ]; then
            echo "Symlink creation ended with errors."
            return 1
        else
            echo "Symlink creation completed successfully."
            return 0
        fi
    else
        echo "No valid iCloud account found."
        return 1
    fi
}

create_symlink() {
    local source="$1"
    local target="$2"

    if [ ! -e "$source" ]; then
        echo "Error: Source '$source' does not exist."
        return 1
    fi

    if [ -e "$target" ]; then
        if [ -L "$target" ]; then
            rm "$target"
        else
            mv "$target" "${target}.backup"
        fi
    fi

    ln -s "$source" "$target"
    echo "Symlink created: $target -> $source"
}

# Run the function if the script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_icloud_signin_and_create_symlinks
fi