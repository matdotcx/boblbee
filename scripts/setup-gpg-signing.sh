#!/usr/bin/env bash

#########################################################
# Title: setup-gpg-signing
# Description: Automatically configure Git GPG signing
# Purpose: Sets up commit and tag signing with existing GPG keys
# Usage: ./setup-gpg-signing.sh
# Requirements: GPG keys already installed, GitHub CLI authenticated
# Source: https://github.com/matdotcx/boblbee
#########################################################

# GPG Signing Setup Script
# Automatically configures Git to use your GPG key for signing
# 
# This script will:
# - Find your existing GPG key by email address
# - Configure Git to use the key for commit and tag signing
# - Add the public key to your GitHub account (if not already present)
# - Verify the configuration is working
#
# Prerequisites:
# - GPG keys must already be installed (via GPG Keychain or gpg --import)
# - If using GPG Keychain, import your .asc secret key file first
# - GitHub CLI must be authenticated (run 'gh auth login' if needed)
# - Your email in the GPG key should match the EMAIL variable below

echo "Setting up GPG signing for Git..."

# Find your GPG key (looks for keys with your email)
EMAIL="diego@iaconelli.org"
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep -B 10 "$EMAIL" | grep "sec" | tail -1 | cut -d'/' -f2 | cut -d' ' -f1)

if [ -z "$KEY_ID" ]; then
    echo "No GPG key found for $EMAIL"
    echo "Available keys:"
    gpg --list-secret-keys --keyid-format=long
    echo ""
    echo "Troubleshooting:"
    echo "- If using GPG Keychain: Import your .asc secret key file"
    echo "- If keys show above but email doesn't match, update EMAIL variable"
    echo "- If no keys shown: gpg --import your-secret-key.asc"
    exit 1
fi

echo "Found GPG key: $KEY_ID"

# Configure Git
git config --global user.signingkey "$KEY_ID"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

echo "Git configuration updated:"
git config --global --list | grep -E "(signingkey|gpgsign)"

# Check if key is on GitHub
echo "Checking GitHub GPG keys..."
if gh auth status &>/dev/null; then
    gh gpg-key list | grep -q "$KEY_ID" && echo "✓ Key already on GitHub" || {
        echo "Adding key to GitHub..."
        gpg --armor --export "$KEY_ID" | gh gpg-key add -
    }
else
    echo "GitHub CLI not authenticated. Run 'gh auth login' first."
fi

echo "✓ GPG signing setup complete!"