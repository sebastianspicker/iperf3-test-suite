#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "pwsh is required but not found in PATH."
  echo "Install PowerShell 7+ from https://learn.microsoft.com/powershell/scripting/install/installing-powershell"
  exit 1
fi

pwsh -NoLogo -NoProfile -File "${ROOT_DIR}/scripts/Invoke-QualityGates.ps1"
