# Edge Optimizer

[![PowerShell Check](https://github.com/Dexin-Y06/edge-optimizer/actions/workflows/powershell.yml/badge.svg)](https://github.com/Dexin-Y06/edge-optimizer/actions/workflows/powershell.yml)
[![Release](https://img.shields.io/github/v/release/Dexin-Y06/edge-optimizer)](https://github.com/Dexin-Y06/edge-optimizer/releases)
[![License](https://img.shields.io/github/license/Dexin-Y06/edge-optimizer)](LICENSE)

A lightweight PowerShell toolkit for optimizing Microsoft Edge on Windows 11.

## What it does

Edge Optimizer configures selected Microsoft Edge policies through the Windows Registry. It focuses on reducing unnecessary Edge background activity, controlling Windows startup behavior, and configuring Sleeping Tabs.

The script also provides backup, restore, and policy verification commands so changes can be checked and recovered.

## Features

- Disable Microsoft Edge Startup Boost
- Disable Microsoft Edge background mode
- Disable automatic Edge startup with Windows
- Enable Sleeping Tabs
- Configure Sleeping Tabs timeout
- Enable automatic tab sleeping/discarding
- Automatically back up existing Edge policies before installation
- Restore the most recent backup
- Check configured Edge policies
- Administrator privilege handling
- GitHub Actions PowerShell validation

## Requirements

- Windows 11
- Microsoft Edge
- PowerShell 5.1 or later
- Administrator privileges for installation and restoration

## Quick Start

Clone the repository:

```powershell
git clone https://github.com/Dexin-Y06/edge-optimizer.git
cd edge-optimizer

Install the optimization:

.\setup.ps1 install

The installation process creates a backup of the existing Edge policies before applying the configured policies.

After installation, restart Microsoft Edge if necessary and verify the policies with:

.\setup.ps1 check
Commands
CommandDescription
installBack up existing policies and apply the optimization
backupCreate a backup of the current Edge policies
restoreRestore the most recent backup
checkCheck the current policy values
helpDisplay command help

Examples:

.\setup.ps1 install
.\setup.ps1 check
.\setup.ps1 backup
.\setup.ps1 restore
.\setup.ps1 help
Default Policies
PolicyValuePurpose
StartupBoostEnabled0Disable Startup Boost
BackgroundModeEnabled0Disable background mode
LaunchEdgeOnWindowsStartupEnabled0Disable automatic startup
SleepingTabsEnabled1Enable Sleeping Tabs
SleepingTabsTimeout15Set the Sleeping Tabs timeout
AutoDiscardSleepingTabsEnabled1Enable automatic sleeping/discarding

Policies are written to:

HKLM\SOFTWARE\Policies\Microsoft\Edge
Verification

You can verify the configuration in three ways.

1. Script check
.\setup.ps1 check

The command compares the current Registry values with the target configuration.

2. Edge policy page

Open the following page in Microsoft Edge:

edge://policy

Select Reload policies and check the relevant policies.

3. Edge performance settings

Open:

edge://settings/performance

Review the Sleeping Tabs settings.

Backup and Restore

Before applying changes, the install command automatically creates a timestamped backup of the existing Edge policies.

Backups are stored locally in:

backups/

The backups/ directory is excluded from Git through .gitignore and is not uploaded to the repository.

To restore the most recent backup:

.\setup.ps1 restore
Safety

This project modifies Microsoft Edge policies in the Windows Registry.

Review the policies before applying them.
The install command creates a backup before changing policies.
The restore command can restore the most recent backup.
Administrator privileges are required for installation and restoration.

Use this tool at your own discretion.

This project is not affiliated with or endorsed by Microsoft.

Project Structure
edge-optimizer/
├── .github/
│   └── workflows/
│       └── powershell.yml
├── backups/              # Local backups, ignored by Git
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── README.md
└── setup.ps1
Continuous Integration

Every push to main and every pull request targeting main runs the PowerShell Check workflow.

The workflow:

Parses setup.ps1 for PowerShell syntax errors.
Runs PSScriptAnalyzer with error-level checks.
Release

The current stable release is v1.0.0.

See the Releases page for version history and release notes.

License

MIT License. See LICENSE.
