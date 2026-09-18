#requires -version 5.1

<#
.SYNOPSIS
    Microsoft Edge Windows 11 优化工具

.DESCRIPTION
    用于配置 Microsoft Edge Policy

    默认配置：

      StartupBoostEnabled                  = 0
      BackgroundModeEnabled                = 0
      LaunchEdgeOnWindowsStartupEnabled    = 0
      SleepingTabsEnabled                  = 1
      SleepingTabsTimeout                  = 15
      AutoDiscardSleepingTabsEnabled       = 1

    支持备份、恢复、检查、状态查看和安全卸载

      .\setup.ps1 install
      .\setup.ps1 backup
      .\setup.ps1 restore
      .\setup.ps1 check
      .\setup.ps1 help
#>

[CmdletBinding()]
param(
    [ValidateSet("install", "backup", "restore", "check", "status", "uninstall", "help")]
    [string]$Action = "install",

    [switch]$WhatIf
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

    Write-Warn "检测到 Microsoft Edge 正在运行。"

    $answer = Read-Host "是否现在结束所有 msedge.exe 进程？(Y/N)"

    if ($answer -match "^[Yy]$") {

        try {

            Get-Process msedge -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction Stop

            Start-Sleep -Milliseconds 800

            Write-Ok "Edge 已成功关闭。"

        }
        catch {

            throw "无法关闭 Edge：$($_.Exception.Message)"
        }

    }
    else {

        throw "用户选择不关闭 Edge，操作已取消。"
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

    Write-Info "     $DisplayName..."

    # 注册表项不存在
    if (-not (Test-Path -LiteralPath $PowerShellPath)) {

        New-EmptyRegFile -Path $OutputFile

        Write-Warn "$DisplayName 当前不存在，已记录为空状态。"

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
#      Registry
# ============================================================

function Backup-Registry {

    Ensure-Directory

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $BackupRoot $timestamp

    $index = 1

    while (Test-Path -LiteralPath $backupDir) {
        $backupDir = Join-Path $BackupRoot "$timestamp-$index"
        $index++
    }

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
# 记录安装前状态
# ============================================================

function Save-PolicyState {

    Ensure-Directory

    $stateFile = Join-Path $BackupRoot "INSTALL_STATE.json"

    if (Test-Path -LiteralPath $stateFile) {
        throw "检测到现有安装状态，Edge Optimizer 可能已经安装。为避免覆盖原始状态，本次安装已停止。"
    }

    $state = [ordered]@{
        Version   = "1.1.0"
        Timestamp = (Get-Date).ToString("o")
        Policies  = [ordered]@{
            HKLM = [ordered]@{}
            HKCU = [ordered]@{}
        }
    }

    foreach ($name in $Policies.Keys) {

        foreach ($scope in @("HKLM", "HKCU")) {

            $keyPath = if ($scope -eq "HKLM") {
                $HklmKey
            }
            else {
                $HkcuKey
            }

            $exists = $false
            $value = $null

            if (Test-Path -LiteralPath $keyPath) {

                $property = Get-ItemProperty `
                    -LiteralPath $keyPath `
                    -Name $name `
                    -ErrorAction SilentlyContinue

                if ($null -ne $property) {

                    $exists = $true
                    $value = $property.$name
                }
            }

            $state.Policies[$scope][$name] = [ordered]@{
                Exists = $exists
                Value  = $value
            }
        }
    }

    $state |
        ConvertTo-Json -Depth 10 |
        Set-Content `
            -LiteralPath $stateFile `
            -Encoding UTF8 `
            -Force

    Write-Ok "已记录安装前 Edge Policy 状态。"

    return $stateFile
}
# ============================================================
# 写入 Edge Policy
# ============================================================

function Set-EdgePolicy {

    Ensure-EdgePolicyKeys

    Write-Host ""

    Write-Info "正在写入 Edge Policy..."

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

    if (-not (Test-Path -LiteralPath $LastBackupFile -PathType Leaf)) {
        throw "找不到 LAST_BACKUP.txt，请先运行 .\setup.ps1 backup 创建备份。"
    }

    $backupDir = (
        Get-Content `
            -LiteralPath $LastBackupFile `
            -Raw `
            -ErrorAction Stop
    ).Trim()

    if ([string]::IsNullOrWhiteSpace($backupDir)) {
        throw "LAST_BACKUP.txt 为空，无法确定最近一次备份。"
    }

    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
        throw "最近一次备份目录不存在：$backupDir"
    }

    $metadataFile = Join-Path `
        $backupDir `
        "backup-metadata.json"

    if (-not (Test-Path -LiteralPath $metadataFile -PathType Leaf)) {
        throw "备份元数据不存在：$metadataFile"
    }

    try {
        $meta = Get-Content `
            -LiteralPath $metadataFile `
            -Raw `
            -ErrorAction Stop |
            ConvertFrom-Json `
            -ErrorAction Stop
    }
    catch {
        throw "备份元数据读取失败：$($_.Exception.Message)"
    }

    if ($null -eq $meta.HKLMExists -or
        $null -eq $meta.HKCUExists) {

        throw "备份元数据格式无效，缺少 HKLMExists 或 HKCUExists。"
    }

    Write-Host ""
    Write-Host "Microsoft Edge Policy 恢复" -ForegroundColor Cyan
    Write-Host "========================================"
    Write-Host ""
    Write-Info "最近一次备份：$backupDir"

    # --------------------------------------------------------
    # HKLM
    # --------------------------------------------------------

    if ([bool]$meta.HKLMExists) {

        if ([string]::IsNullOrWhiteSpace($meta.HKLMFile)) {
            throw "备份元数据缺少 HKLM 备份文件路径。"
        }

        if (-not (Test-Path -LiteralPath $meta.HKLMFile -PathType Leaf)) {
            throw "HKLM 备份文件不存在：$($meta.HKLMFile)"
        }

        Write-Info "正在恢复 HKLM Edge Policy..."

        $regProcess = Start-Process `
            -FilePath "reg.exe" `
            -ArgumentList @(
                "import",
                ('"{0}"' -f $meta.HKLMFile)
            ) `
            -Wait `
            -PassThru `
            -NoNewWindow

        if ($regProcess.ExitCode -ne 0) {
            throw "HKLM Edge Policy 恢复失败，reg.exe 返回代码：$($regProcess.ExitCode)"
        }

        Write-Ok "HKLM Edge Policy 已恢复。"
    }
    else {

        Write-Info "安装前不存在 HKLM Edge Policy，正在清理 Optimizer 策略..."

        if (Test-Path -LiteralPath $HklmKey) {

            foreach ($name in $Policies.Keys) {

                Remove-ItemProperty `
                    -Path $HklmKey `
                    -Name $name `
                    -ErrorAction SilentlyContinue
            }
        }

        Write-Ok "HKLM Optimizer 策略已清理。"
    }

    # --------------------------------------------------------
    # HKCU
    # --------------------------------------------------------

    if ([bool]$meta.HKCUExists) {

        if ([string]::IsNullOrWhiteSpace($meta.HKCUFile)) {
            throw "备份元数据缺少 HKCU 备份文件路径。"
        }

        if (-not (Test-Path -LiteralPath $meta.HKCUFile -PathType Leaf)) {
            throw "HKCU 备份文件不存在：$($meta.HKCUFile)"
        }

        Write-Info "正在恢复 HKCU Edge Policy..."

        $regProcess = Start-Process `
            -FilePath "reg.exe" `
            -ArgumentList @(
                "import",
                ('"{0}"' -f $meta.HKCUFile)
            ) `
            -Wait `
            -PassThru `
            -NoNewWindow

        if ($regProcess.ExitCode -ne 0) {
            throw "HKCU Edge Policy 恢复失败，reg.exe 返回代码：$($regProcess.ExitCode)"
        }

        Write-Ok "HKCU Edge Policy 已恢复。"
    }
    else {

        Write-Info "安装前不存在 HKCU Edge Policy，无需恢复。"
    }

    Write-Host ""
    Write-Ok "Edge Policy 恢复完成。"
    Write-Host ""
}

function Check-Policies {

    Write-Host ""
    Write-Host "Microsoft Edge Policy    " -ForegroundColor Cyan
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

    Write-Info "正在检查当前 Edge Policy..."
    }
    else {

        Write-Warn "存在未匹配项。"
        Write-Info "打开 edge://policy，然后点击 Reload policies。"
    }

    Write-Host ""

    Write-Info "建议打开 edge://policy 检查实际生效状态。"
    Write-Info "也可查看 edge://settings/performance 检查 Sleeping Tabs。"
}

# ============================================================
# 卸载 Edge Optimizer
# ============================================================

function Uninstall-EdgeOptimizer {

    $stateFile = Join-Path $BackupRoot "INSTALL_STATE.json"

    if (-not (Test-Path -LiteralPath $stateFile)) {
        throw "找不到安装状态文件，无法安全卸载。请先使用 v1.1.0 执行一次 install。"
    }

    try {
        $state = Get-Content `
            -LiteralPath $stateFile `
            -Raw |
            ConvertFrom-Json `
            -ErrorAction Stop
    }
    catch {
        throw "安装状态文件读取失败，无法安全卸载：$($_.Exception.Message)"
    }

    if ($null -eq $state.Policies) {
        throw "安装状态文件格式无效，无法安全卸载。"
    }

    Write-Host ""
    Write-Host "Microsoft Edge Optimizer 卸载检查" -ForegroundColor Cyan
    Write-Host "========================================"
    Write-Host ""

    $restorePlan = @()
    $skipped = @()

    foreach ($name in $Policies.Keys) {

        $saved = $state.Policies.HKLM.$name

        if ($null -eq $saved) {
            $skipped += [pscustomobject]@{
                Name   = $name
                Reason = "没有保存的原始状态"
            }
            continue
        }

        $current = Get-PolicyValue `
            -Path $HklmKey `
            -Name $name

        $target = $Policies[$name]

        # 当前值仍然是 Optimizer 写入的目标值
        if ($null -ne $current -and
            [string]$current -eq [string]$target) {

            $restorePlan += [pscustomobject]@{
                Name   = $name
                Saved  = $saved
                Action = if ([bool]$saved.Exists) {
                    "恢复为 $($saved.Value)"
                }
                else {
                    "删除"
                }
            }

            continue
        }

        # 当前值已经被用户或其他程序修改
        if ($null -ne $current) {

            $skipped += [pscustomobject]@{
                Name   = $name
                Reason = "当前值 $current 与 Optimizer 目标值 $target 不同"
            }

            continue
        }

        # 当前不存在
        if ([bool]$saved.Exists) {

            $restorePlan += [pscustomobject]@{
                Name   = $name
                Saved  = $saved
                Action = "恢复为 $($saved.Value)"
            }
        }
        else {

            $skipped += [pscustomobject]@{
                Name   = $name
                Reason = "当前未设置，且安装前也未设置"
            }
        }
    }

    if ($restorePlan.Count -eq 0) {

        Write-Host "没有可以安全恢复的 Edge Policy。" -ForegroundColor Yellow

        if ($skipped.Count -gt 0) {

            Write-Host ""
            Write-Host "已跳过：" -ForegroundColor Yellow

            foreach ($item in $skipped) {
                Write-Host (
                    "  {0,-38} {1}" -f
                    $item.Name,
                    $item.Reason
                ) -ForegroundColor Yellow
            }
        }

        Write-Host ""
        Write-Info "本次卸载未修改 Registry，也未关闭 Edge。"
        Write-Host ""

        return
    }

    if (-not $WhatIf) {

        Write-Host "卸载计划：" -ForegroundColor Cyan
        Write-Host ""

        foreach ($item in $restorePlan) {

            Write-Host (
                "  {0,-38} {1}" -f
                $item.Name,
                $item.Action
            )
        }

        if ($skipped.Count -gt 0) {

            Write-Host ""
            Write-Host "以下策略将跳过，不覆盖用户修改：" -ForegroundColor Yellow
            Write-Host ""

            foreach ($item in $skipped) {

                Write-Host (
                    "  {0,-38} {1}" -f
                    $item.Name,
                    $item.Reason
                ) -ForegroundColor Yellow
            }
        }

        Write-Host ""
    }
    if ($WhatIf) {

        Write-Host "WhatIf 卸载预览：" -ForegroundColor Cyan
        Write-Host ""

        foreach ($item in $restorePlan) {

            Write-Host (
                "  {0,-38} {1}" -f
                $item.Name,
                $item.Action
            )
        }

        if ($skipped.Count -gt 0) {

            Write-Host ""
            Write-Host "以下策略将被跳过：" -ForegroundColor Yellow
            Write-Host ""

            foreach ($item in $skipped) {

                Write-Host (
                    "  {0,-38} {1}" -f
                    $item.Name,
                    $item.Reason
                ) -ForegroundColor Yellow
            }
        }

        Write-Host ""
        Write-Ok "WhatIf 卸载预览完成，系统未发生修改。"
        Write-Host ""

        return
    }

    if (-not (Test-IsAdministrator)) {
        throw "uninstall 需要管理员 PowerShell。请右键 PowerShell -> 以管理员身份运行。"
    }

    Close-Edge

    $restoredCount = 0

    foreach ($item in $restorePlan) {

        $name = $item.Name
        $saved = $item.Saved

        try {

            if ([bool]$saved.Exists) {

                if (-not (Test-Path -LiteralPath $HklmKey)) {

                    New-Item `
                        -Path $HklmKey `
                        -Force |
                        Out-Null
                }

                New-ItemProperty `
                    -Path $HklmKey `
                    -Name $name `
                    -PropertyType DWord `
                    -Value ([int]$saved.Value) `
                    -Force `
                    -ErrorAction Stop |
                    Out-Null

                Write-Ok "$name 已恢复为 $($saved.Value)"
            }
            else {

                if (Test-Path -LiteralPath $HklmKey) {

                    Remove-ItemProperty `
                        -Path $HklmKey `
                        -Name $name `
                        -ErrorAction SilentlyContinue
                }

                Write-Ok "$name 已删除（安装前不存在）"
            }

            $restoredCount++
        }
        catch {
            throw "恢复 $name 失败：$($_.Exception.Message)"
        }
    }

    Write-Host ""

    Write-Ok "Edge Optimizer 卸载完成。"
    Write-Info "已处理 $restoredCount 项策略。"

    if ($skipped.Count -gt 0) {

        Write-Warn "有 $($skipped.Count) 项策略因检测到变化而被跳过。"
    }

    Write-Host ""
    if ($skipped.Count -eq 0) {

        try {
            Remove-Item `
                -LiteralPath $stateFile `
                -Force `
                -ErrorAction Stop

            Write-Ok "安装状态已清理。"
        }
        catch {
            Write-Warn "Registry 已恢复，但安装状态文件删除失败：$($_.Exception.Message)"
        }
    }
    else {

        Write-Warn "由于存在被跳过的策略，INSTALL_STATE.json 将被保留。"
        Write-Info "处理完剩余策略后可再次运行 uninstall。"
    }
    Write-Info "建议运行：.\setup.ps1 status"
    Write-Host ""
}
# ============================================================
# 状态
# ============================================================

function Status-Policies {

    Write-Host ""
    Write-Host "Microsoft Edge Optimizer 状态" -ForegroundColor Cyan
    Write-Host "========================================"

    $configured = 0
    $total = $Policies.Count

    foreach ($name in $Policies.Keys) {

        $current = Get-PolicyValue `
            -Path $HklmKey `
            -Name $name

        if ($null -eq $current) {
            $current = Get-PolicyValue `
                -Path $HkcuKey `
                -Name $name
        }

        if ($null -eq $current) {

            Write-Host ("{0,-38} 未设置" -f $name) -ForegroundColor Yellow
            continue
        }

        $target = $Policies[$name]

        if ([string]$current -eq [string]$target) {

            Write-Host ("{0,-38} 已配置" -f $name) -ForegroundColor Green
            $configured++
        }
        else {

            Write-Host ("{0,-38} 配置冲突 (当前={1}, 目标={2})" -f $name, $current, $target) -ForegroundColor Red
        }
    }

    Write-Host ""

    if ($configured -eq $total) {

        Write-Ok "Edge Optimizer 当前处于完整配置状态。"
    }
    elseif ($configured -eq 0) {

        Write-Warn "Edge Optimizer 当前未配置。"
    }
    else {

        Write-Warn "Edge Optimizer 当前处于部分配置状态。"
    }

    Write-Host ""
    Write-Host "提示："
    Write-Host "可运行 .\setup.ps1 check 查看详细策略检查结果。"
    Write-Host ""
}# ============================================================
# 安装预览
# ============================================================

function Show-InstallPreview {

    Write-Host ""
    Write-Host "Microsoft Edge Windows 11 优化安装预览" -ForegroundColor Cyan
    Write-Host "========================================"
    Write-Host ""

    Write-Host "以下操作将在实际安装时执行：" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "  1. 关闭 Microsoft Edge"
    Write-Host "  2. 备份当前 Edge Policy"
    Write-Host "  3. 写入以下优化策略："
    Write-Host ""

    foreach ($name in $Policies.Keys) {

        $target = $Policies[$name]

        Write-Host ("     {0,-38} -> {1}" -f $name, $target)
    }

    Write-Host ""
    Write-Host "预览模式不会执行以下操作：" -ForegroundColor Green
    Write-Host "  - 不关闭 Edge"
    Write-Host "  - 不创建 Registry 备份"
    Write-Host "  - 不修改 Registry"
    Write-Host ""
    Write-Ok "WhatIf 预览完成，系统未发生修改。"
    Write-Host ""
}# ============================================================
# 帮助
# ============================================================

function Show-Help {

    @"

Microsoft Edge Windows 11 优化工具
========================================

用法：

  .\setup.ps1 install
      备份当前 Edge Policy，然后写入优化策略。

  .\setup.ps1 install -WhatIf
      预览安装将执行的操作，不修改系统。

  .\setup.ps1 backup
      仅备份当前 Edge Policy。

  .\setup.ps1 restore
      恢复最近一次备份。

  .\setup.ps1 check
      检查当前 Registry 中的策略。

  .\setup.ps1 status
      查看 Edge Optimizer 当前配置状态。

  .\setup.ps1 uninstall
      安全卸载 Edge Optimizer，并恢复安装前的策略状态。

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
        # STATUS
        # ----------------------------------------------------

        "status" {

            Status-Policies
        }

        # ----------------------------------------------------
        # UNINSTALL
        # ----------------------------------------------------

        "uninstall" {

            Uninstall-EdgeOptimizer
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

            if ($WhatIf) {

                Write-Host ""
                Write-Host "Microsoft Edge Windows 11 优化恢复预览"
                Write-Host "========================================"
                Write-Host "以下操作将在实际 restore 时执行："
                Write-Host "  1. 检查管理员权限"
                Write-Host "  2. 关闭 Microsoft Edge"
                Write-Host "  3. 恢复最近一次 Registry 备份"
                Write-Host ""
                Write-Host "预览模式不会执行以下操作："
                Write-Host "  - 不关闭 Edge"
                Write-Host "  - 不修改 Registry"
                Write-Host ""
                Write-Ok "WhatIf 预览完成，系统未发生修改。"

                return
            }

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

            if ($WhatIf) {

                Show-InstallPreview
                return
            }

            if (-not (Test-IsAdministrator)) {

                Write-Info "正在请求管理员权限..."

                $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" install' -f $PSCommandPath

                Start-Process `
                    powershell.exe `
                    -Verb RunAs `
                    -ArgumentList $arg

                exit
            }

            $stateFile = Join-Path $BackupRoot "INSTALL_STATE.json"

            if (Test-Path -LiteralPath $stateFile) {

                throw "检测到现有安装状态，Edge Optimizer 可能已经安装。为避免重复安装和覆盖原始状态，本次安装已停止。"
            }

            Write-Host ""
            Write-Host "Microsoft Edge Windows 11 优化安装" -ForegroundColor Cyan
            Write-Host "========================================"
            Write-Host ""

            Close-Edge

            Write-Host ""

            $backupDir = Backup-Registry

            Write-Host ""

            $stateFile = Save-PolicyState

            Write-Host ""

            Set-EdgePolicy

            Write-Host ""

            Write-Ok "安装完成。"

            Write-Host ""
            Write-Info "下一步："
            Write-Host "1.    Microsoft Edge"
            Write-Host "2. 地址栏输入：edge://policy"
            Write-Host "3.     Reload policies"
            Write-Host "4. 再运行：.\setup.ps1 check"
            Write-Host ""

            Write-Host "    备份目录：" -NoNewline
            Write-Host $backupDir -ForegroundColor Cyan

            Write-Host ""
        }
    }
}
catch {

    Write-Err "    : $($_.Exception.Message)"

    exit 1
}
