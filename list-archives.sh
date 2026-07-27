#!/usr/bin/env bash
set -euo pipefail

if ! command -v pwsh &>/dev/null; then
    echo "Error: PowerShell (pwsh) is not installed."
    echo ""
    echo "Install it with:"
    echo "  macOS:   brew install powershell"
    echo "  Debian:  sudo apt install powershell"
    echo "  Ubuntu:  sudo snap install powershell --classic"
    echo "  Fedora:  sudo dnf install powershell"
    echo ""
    echo "See https://github.com/PowerShell/PowerShell for more options."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec pwsh -NoProfile -File "$SCRIPT_DIR/list-archives.ps1" "$@"
