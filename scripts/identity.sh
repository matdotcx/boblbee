#!/bin/bash

check_icloud_signin_and_create_symlinks() {
    local account_info=$(defaults read MobileMeAccounts 2>/dev/null)

    if [[ -z "$account_info" ]]; then
        echo "No iCloud account found."
        return 1
    fi

    local account_id=$(echo "$account_info" | sed -n '/AccountID/,/;/p' | awk -F'"' '{print $2; exit}')

    if [[ -n "$account_id" ]]; then
        echo "iCloud account detected: $account_id"
        create_symlink ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/Ark/Sync/System/.ssh ~/.ssh
        create_symlink ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/Ark/Sync/System/.zshrc ~/.zshrc
        echo "Symlink creation completed."
        return 0
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
