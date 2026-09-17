#requires -version 5.1

<#
.SYNOPSIS
    Microsoft Edge Windows 11 优化 / 备份 / 恢复 / 检查脚本

.DESCRIPTION
    安全写入 Microsoft Edge Policy。

    默认策略：

      StartupBoostEnabled                  = 0
      BackgroundModeEnabled                = 0
      LaunchEdgeOnWindowsStartupEnabled    = 0
      SleepingTabsEnabled                  = 1
      SleepingTabsTimeout                  = 15
      AutoDiscardSleepingTabsEnabled       = 1

    支持：

      .\setup.ps1 install
      .\setup.ps1 backup
      .\setup.ps1 restore
      .\setup.ps1 check
      .\setup.ps1 help
#>

[CmdletBinding()]
param(
    [ValidateSet("install", "backup", "restore", "check", "help")]
    [string]$Action = "install"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 基础配置
# ============================================================

$EdgePolicySubKey = "SOFTWARE\Policies\Microsoft\Edge"

$HklmKey = "HKLM:\$EdgePolicySubKey"
$HkcuKey = "HKCU:\$EdgePolicySubKey"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$BackupRoot = Join-Path $ScriptRoot "backups"
$LastBackupFile = Join-Path $BackupRoot "LAST_BACKUP.txt"

# ============================================================
# Edge Policy
# ============================================================

$Policies = [ordered]@{
    StartupBoostEnabled               = 0
    BackgroundModeEnabled             = 0
    LaunchEdgeOnWindowsStartupEnabled = 0
    SleepingTabsEnabled               = 1
    SleepingTabsTimeout               = 15
    AutoDiscardSleepingTabsEnabled    = 1
}

# ============================================================
# 输出函数
# ============================================================

function Write-Info {
    param(
        [string]$Message
    )

    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param(
        [string]$Message
    )

    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param(
        [string]$Message
    )

    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param(
        [string]$Message
    )

    Write-Host "[ERR ] $Message" -ForegroundColor Red
}

# ============================================================
# 管理员检查
# ============================================================

function Test-IsAdministrator {

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object Security.Principal.WindowsPrincipal(
        $currentIdentity
    )

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

# ============================================================
# 创建备份目录
# ============================================================

function Ensure-Directory {

    if (-not (Test-Path -LiteralPath $BackupRoot)) {

        New-Item `
            -Path $BackupRoot `
            -ItemType Directory `
            -Force | Out-Null
    }
}

# ============================================================
# 关闭 Edge
# ============================================================

function Close-Edge {

    $edge = Get-Process msedge -ErrorAction SilentlyContinue

    if (-not $edge) {
        Write-Ok "Edge 当前未运行。"
        return
    }

    Write-Warn "检测到 Edge 正在运行。"

    $answer = Read-Host "是否现在结束所有 msedge.exe 进程？(Y/N)"

    if ($answer -match "^[Yy]$") {

        try {

            Get-Process msedge -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction Stop

            Start-Sleep -Milliseconds 800

            Write-Ok "Edge 进程已关闭。"

        }
        catch {

            throw "无法关闭 Edge：$($_.Exception.Message)"
        }

    }
    else {

        Write-Warn "你选择不关闭 Edge。继续执行可能导致策略不会立即刷新。"
    }
}

# ============================================================
# 创建空 .reg 文件
# ============================================================

function New-EmptyRegFile {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = @(
        "Windows Registry Editor Version 5.00"
        ""
    )

    Set-Content `
        -LiteralPath $Path `
        -Value $content `
        -Encoding Unicode `
        -Force
}

# ============================================================
# 导出注册表
#
# 关键修复：
# 先 Test-Path。
#
# 如果 Edge Policy 不存在：
#   不调用 reg.exe export
#   直接记录为空状态
#
# 这样不会再出现：
#   系统找不到指定的注册表项或值
# ============================================================

function Export-RegistryKeySafe {

    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string]$RegPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    Write-Info "备份 $DisplayName..."

    # 注册表项不存在
    if (-not (Test-Path -LiteralPath $PowerShellPath)) {

        New-EmptyRegFile -Path $OutputFile

        Write-Warn "$DisplayName 键当前不存在，已记录为空状态。"

        return $false
    }

    # 注册表项存在，才执行 reg.exe
    $regOutput = & reg.exe export $RegPath $OutputFile /y 2>&1

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {

        $message = ($regOutput | Out-String).Trim()

        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "reg.exe 退出码：$exitCode"
        }

        throw "$DisplayName 备份失败：$message"
    }

    Write-Ok "$DisplayName 备份：$OutputFile"

    return $true
}

# ============================================================
# 备份 Registry
# ============================================================

function Backup-Registry {

    Ensure-Directory

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $backupDir = Join-Path $BackupRoot $timestamp

    New-Item `
        -Path $backupDir `
        -ItemType Directory `
        -Force | Out-Null

    $hklmFile = Join-Path `
        $backupDir `
        "Edge-Policy-HKLM.reg"

    $hkcuFile = Join-Path `
        $backupDir `
        "Edge-Policy-HKCU.reg"

    # HKLM
    $hklmExists = Export-RegistryKeySafe `
        -PowerShellPath $HklmKey `
        -RegPath "HKLM\$EdgePolicySubKey" `
        -OutputFile $hklmFile `
        -DisplayName "HKLM Edge Policy"

    # HKCU
    $hkcuExists = Export-RegistryKeySafe `
        -PowerShellPath $HkcuKey `
        -RegPath "HKCU\$EdgePolicySubKey" `
        -OutputFile $hkcuFile `
        -DisplayName "HKCU Edge Policy"

    # 元数据
    $meta = [ordered]@{
        Timestamp  = (Get-Date).ToString("o")
        HKLMExists = $hklmExists
        HKCUExists = $hkcuExists
        HKLMFile   = $hklmFile
        HKCUFile   = $hkcuFile
    }

    $metaFile = Join-Path `
        $backupDir `
        "backup-metadata.json"

    $meta |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -LiteralPath $metaFile `
            -Encoding UTF8 `
            -Force

    Set-Content `
        -LiteralPath $LastBackupFile `
        -Value $backupDir `
        -Encoding UTF8 `
        -Force

    Write-Ok "备份完成：$backupDir"

    return $backupDir
}

# ============================================================
# 创建 Edge Policy 注册表项
# ============================================================

function Ensure-EdgePolicyKeys {

    if (-not (Test-Path -LiteralPath $HklmKey)) {

        Write-Info "HKLM Edge Policy 不存在，正在创建..."

        New-Item `
            -Path $HklmKey `
            -Force | Out-Null

        Write-Ok "HKLM Edge Policy 已创建。"
    }
}

# ============================================================
# 写入 Edge Policy
# ============================================================

function Set-EdgePolicy {

    Ensure-EdgePolicyKeys

    Write-Host ""

    Write-Info "开始写入 Edge 优化策略..."

    foreach ($name in $Policies.Keys) {

        $value = [int]$Policies[$name]

        try {

            New-ItemProperty `
                -Path $HklmKey `
                -Name $name `
                -PropertyType DWord `
                -Value $value `
                -Force `
                -ErrorAction Stop |
                Out-Null

            Write-Ok "$name = $value"
        }
        catch {

            throw "写入策略 $name 失败：$($_.Exception.Message)"
        }
    }

    Write-Ok "已写入 HKLM Edge Policy。"
}

# ============================================================
# 获取策略值
# ============================================================

function Get-PolicyValue {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {

        $item = Get-ItemProperty `
            -Path $Path `
            -Name $Name `
            -ErrorAction Stop

        return $item.$Name
    }
    catch {

        return $null
    }
}

# ============================================================
# 删除本脚本写入的策略
# ============================================================

function Remove-OurPolicies {

    if (Test-Path -LiteralPath $HklmKey) {

        foreach ($name in $Policies.Keys) {

            Remove-ItemProperty `
                -Path $HklmKey `
                -Name $name `
                -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path -LiteralPath $HkcuKey) {

        foreach ($name in $Policies.Keys) {

            Remove-ItemProperty `
                -Path $HkcuKey `
                -Name $name `
                -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 恢复 Registry
# ============================================================

function Restore-Registry {

    Ensure-Directory

    if (-not (Test-Path -LiteralPath $LastBackupFile)) {

        throw "没有找到 LAST_BACKUP.txt。请先执行 .\setup.ps1 backup"
    }

    $backupDir = (
        Get-Content `
            -LiteralPath $LastBackupFile `
            -Raw
    ).Trim()

    if (-not (Test-Path -LiteralPath $backupDir)) {

        throw "备份目录不存在：$backupDir"
    }

    $metadataFile = Join-Path `
        $backupDir `
        "backup-metadata.json"

    if (-not (Test-Path -LiteralPath $metadataFile)) {

        throw "备份元数据不存在：$metadataFile"
    }

    $meta = Get-Content `
        -LiteralPath $metadataFile `
        -Raw |
        ConvertFrom-Json

    Write-Info "正在恢复上一次备份：$backupDir"

    # 删除本脚本当前写入的策略
    Remove-OurPolicies

    # --------------------------------------------------------
    # HKLM
    # --------------------------------------------------------

    if (
        $meta.HKLMExists -and
        (Test-Path -LiteralPath $meta.HKLMFile)
    ) {

        & reg.exe import $meta.HKLMFile 2>&1 |
            Out-Null

        if ($LASTEXITCODE -ne 0) {

            throw "HKLM 恢复失败。"
        }

        Write-Ok "HKLM Edge Policy 已恢复。"
    }
    else {

        Write-Info "原始 HKLM Edge Policy 不存在，保持为空。"
    }

    # --------------------------------------------------------
    # HKCU
    # --------------------------------------------------------

    if (
        $meta.HKCUExists -and
        (Test-Path -LiteralPath $meta.HKCUFile)
    ) {

        & reg.exe import $meta.HKCUFile 2>&1 |
            Out-Null

        if ($LASTEXITCODE -ne 0) {

            throw "HKCU 恢复失败。"
        }

        Write-Ok "HKCU Edge Policy 已恢复。"
    }
    else {

        Write-Info "原始 HKCU Edge Policy 不存在，保持为空。"
    }

    Write-Ok "恢复完成。"
}

# ============================================================
# 检查策略
# ============================================================

function Check-Policies {

    Write-Host ""
    Write-Host "Microsoft Edge Policy 检查" -ForegroundColor Cyan
    Write-Host "========================================"

    $allGood = $true

    foreach ($name in $Policies.Keys) {

        $expected = [int]$Policies[$name]

        $hklm = Get-PolicyValue `
            -Path $HklmKey `
            -Name $name

        $hkcu = Get-PolicyValue `
            -Path $HkcuKey `
            -Name $name

        if ($null -ne $hklm) {

            $actual = $hklm
            $scope = "HKLM"
        }
        elseif ($null -ne $hkcu) {

            $actual = $hkcu
            $scope = "HKCU"
        }
        else {

            $actual = "<未设置>"
            $scope = "-"
        }

        $status = ($actual -eq $expected)

        if ($status) {

            Write-Host (
                "{0,-38} {1,-6} 当前={2} 目标={3}" -f
                $name,
                $scope,
                $actual,
                $expected
            ) -ForegroundColor Green
        }
        else {

            Write-Host (
                "{0,-38} {1,-6} 当前={2} 目标={3}" -f
                $name,
                $scope,
                $actual,
                $expected
            ) -ForegroundColor Yellow

            $allGood = $false
        }
    }

    Write-Host ""

    if ($allGood) {

        Write-Ok "本地 Registry 中的优化策略与目标一致。"
    }
    else {

        Write-Warn "存在未匹配项。"
        Write-Info "打开 edge://policy，然后点击 Reload policies。"
    }

    Write-Host ""

    Write-Info "建议打开 edge://policy 检查实际生效状态。"
    Write-Info "也可以打开 edge://settings/performance 检查 Sleeping Tabs。"
}

# ============================================================
# 帮助
# ============================================================

function Show-Help {

    @"

Microsoft Edge Windows 11 优化工具
========================================

用法：

  .\setup.ps1 install
      备份当前 Edge Policy，然后写入优化策略。

  .\setup.ps1 backup
      仅备份当前 Edge Policy。

  .\setup.ps1 restore
      恢复最近一次备份。

  .\setup.ps1 check
      检查当前 Registry 中的策略。

  .\setup.ps1 help
      显示帮助。

默认策略：

  StartupBoostEnabled                  = 0
  BackgroundModeEnabled                = 0
  LaunchEdgeOnWindowsStartupEnabled    = 0
  SleepingTabsEnabled                  = 1
  SleepingTabsTimeout                  = 15
  AutoDiscardSleepingTabsEnabled       = 1

备份位置：

  $BackupRoot

========================================

"@
}

# ============================================================
# 主程序
# ============================================================

try {

    switch ($Action) {

        # ----------------------------------------------------
        # HELP
        # ----------------------------------------------------

        "help" {

            Show-Help
        }

        # ----------------------------------------------------
        # CHECK
        # ----------------------------------------------------

        "check" {

            Check-Policies
        }

        # ----------------------------------------------------
        # BACKUP
        # ----------------------------------------------------

        "backup" {

            if (-not (Test-IsAdministrator)) {

                Write-Warn "backup 最好使用管理员 PowerShell。"
                Write-Warn "当前不是管理员，继续尝试。"
            }

            $null = Backup-Registry
        }

        # ----------------------------------------------------
        # RESTORE
        # ----------------------------------------------------

        "restore" {

            if (-not (Test-IsAdministrator)) {

                throw "restore 需要管理员 PowerShell。请右键 PowerShell -> 以管理员身份运行。"
            }

            Close-Edge

            Restore-Registry
        }

        # ----------------------------------------------------
        # INSTALL
        # ----------------------------------------------------

        "install" {

            if (-not (Test-IsAdministrator)) {

                Write-Info "正在请求管理员权限..."

                $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" install' -f $PSCommandPath

                Start-Process `
                    powershell.exe `
                    -Verb RunAs `
                    -ArgumentList $arg

                exit
            }

            Write-Host ""
            Write-Host "Microsoft Edge Windows 11 优化安装" -ForegroundColor Cyan
            Write-Host "========================================"
            Write-Host ""

            Close-Edge

            Write-Host ""

            $backupDir = Backup-Registry

            Write-Host ""

            Set-EdgePolicy

            Write-Host ""

            Write-Ok "安装完成。"

            Write-Host ""
            Write-Info "下一步："
            Write-Host "1. 打开 Microsoft Edge"
            Write-Host "2. 地址栏输入：edge://policy"
            Write-Host "3. 点击 Reload policies"
            Write-Host "4. 再运行：.\setup.ps1 check"
            Write-Host ""

            Write-Host "备份目录：" -NoNewline
            Write-Host $backupDir -ForegroundColor Cyan

            Write-Host ""
        }
    }
}
catch {

    Write-Err "错误: $($_.Exception.Message)"

    exit 1
}