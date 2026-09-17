Edge Optimizer

A lightweight PowerShell toolkit for optimizing Microsoft Edge on Windows 11.

Features
Disable Microsoft Edge Startup Boost
Disable Microsoft Edge background mode
Disable automatic Edge startup with Windows
Enable Sleeping Tabs
Configure Sleeping Tabs timeout
Enable automatic tab sleeping/discarding
Automatically back up existing Edge policies before installation
Restore the most recent backup
Check configured Edge policies
Requirements
Windows 11
Microsoft Edge
PowerShell 5.1 or later
Administrator privileges for installation and restoration
Usage

Open PowerShell and navigate to the project directory:

cd D:\Dev\edge-optimizer

Install the optimization:

.\setup.ps1 install

Check the current configuration:

.\setup.ps1 check

Create a backup:

.\setup.ps1 backup

Restore the most recent backup:

.\setup.ps1 restore

Display help:

.\setup.ps1 help

Policies

The default configuration is:

Policy	Value
StartupBoostEnabled	0
BackgroundModeEnabled	0
LaunchEdgeOnWindowsStartupEnabled	0
SleepingTabsEnabled	1
SleepingTabsTimeout	15
AutoDiscardSleepingTabsEnabled	1

These policies are written to:

HKLM\SOFTWARE\Policies\Microsoft\Edge

Backup and Restore

Before applying changes, the install command automatically creates a timestamped backup of the existing Edge policies.

Backups are stored locally in:

backups/

The backups/ directory is excluded from Git through .gitignore.

To restore the most recent backup:

.\setup.ps1 restore

Verification

After installation, open:

edge://policy

Then select Reload policies.

You can also open:

edge://settings/performance

to review Sleeping Tabs settings.

The check command verifies the values currently present in the Windows Registry.

Safety

This project modifies Microsoft Edge policies in the Windows Registry.

The install command creates a backup before applying changes.

The restore command can restore the most recent backup.

Use this tool at your own discretion.

This project is not affiliated with or endorsed by Microsoft.

Project Structure

edge-optimizer/
├── setup.ps1
├── README.md
├── LICENSE
├── CHANGELOG.md
├── .gitignore
└── backups/
└── (local backups, ignored by Git)

License

MIT License