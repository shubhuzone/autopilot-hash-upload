<#
.SYNOPSIS
    Collects the Windows Autopilot hardware hash and uploads it to Intune.
    Uses interactive admin sign-in (browser/device-code popup) - no app registration needed.

.USAGE
    powershell.exe -ExecutionPolicy Bypass -File Upload-AutopilotHash-Interactive.ps1
    Run as Administrator. A sign-in prompt will appear - log in with your admin account.
#>

[CmdletBinding()]
param(
    [string]$GroupTag = "",
    [string]$LogPath  = "$env:ProgramData\AutopilotUpload\upload.log",
    [switch]$RestartAfter   # auto-restart device once upload succeeds (useful at OOBE)
)

$ErrorActionPreference = "Stop"

# Reset PSModulePath to only the standard machine/user paths. This avoids a known
# issue where PowerShell 7 (pwsh) module paths leak into a Windows PowerShell 5.1
# session and cause "module found but could not be loaded" errors for
# PackageManagement / PowerShellGet.
$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PSModulePath","User")

New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null

function Write-Log { param($msg) Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # --- Step 1: NuGet provider (non-fatal, time-boxed - Install-Script/Install-Module
    # will also try to pull this in on their own if it's still missing) ---
    Write-Log "Ensuring NuGet provider..."
    try {
        Import-Module PackageManagement -Force -ErrorAction Stop
        $hasNuGet = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $hasNuGet) {
            $job = Start-Job -ScriptBlock {
                $ConfirmPreference = 'None'
                $ProgressPreference = 'SilentlyContinue'
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -Scope AllUsers
            }
            $done = Wait-Job -Job $job -Timeout 45
            if (-not $done) {
                Stop-Job -Job $job | Out-Null
                throw "Install-PackageProvider timed out after 45s (likely a network/proxy block reaching the NuGet provider feed)."
            }
            Receive-Job -Job $job -ErrorAction Stop | Out-Null
            Remove-Job -Job $job -Force
        }
    }
    catch {
        Write-Log "WARNING: NuGet provider check/install failed ($($_.Exception.Message)) - continuing, later steps will retry it."
    }
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop -WarningAction SilentlyContinue
    }
    catch {
        Write-Log "WARNING: Set-PSRepository failed ($($_.Exception.Message)) - continuing anyway."
    }

    # --- Step 2: Get-WindowsAutopilotInfo script (fatal if this fails - we can't continue without it) ---
    Write-Log "Ensuring Get-WindowsAutopilotInfo script..."
    if (-not (Get-InstalledScript -Name Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue)) {
        $job = Start-Job -ScriptBlock {
            $ConfirmPreference = 'None'
            $ProgressPreference = 'SilentlyContinue'
            Install-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false -Scope AllUsers
        }
        $done = Wait-Job -Job $job -Timeout 90
        if (-not $done) {
            Stop-Job -Job $job | Out-Null
            Remove-Job -Job $job -Force
            throw "Install-Script for Get-WindowsAutopilotInfo timed out after 90s - check internet/proxy access to PowerShell Gallery."
        }
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
        Remove-Job -Job $job -Force
    }

    # --- Step 3: WindowsAutopilotIntune module (non-fatal, time-boxed - Get-WindowsAutopilotInfo
    # will pull it in itself if missing) ---
    try {
        if (-not (Get-Module -ListAvailable -Name WindowsAutopilotIntune)) {
            $job = Start-Job -ScriptBlock {
                $ConfirmPreference = 'None'
                $ProgressPreference = 'SilentlyContinue'
                Install-Module -Name WindowsAutopilotIntune -Force -Confirm:$false -Scope AllUsers -AllowClobber
            }
            $done = Wait-Job -Job $job -Timeout 90
            if (-not $done) {
                Stop-Job -Job $job | Out-Null
                Remove-Job -Job $job -Force
                throw "Install-Module for WindowsAutopilotIntune timed out after 90s."
            }
            Receive-Job -Job $job -ErrorAction Stop | Out-Null
            Remove-Job -Job $job -Force
        }
    }
    catch {
        Write-Log "WARNING: WindowsAutopilotIntune module pre-install failed ($($_.Exception.Message)) - continuing, the next step will retry it."
    }

    # Resolve the installed script's path robustly - Get-InstalledScript's object
    # doesn't reliably expose a usable .Path property across PowerShellGet versions.
    $scriptPath = $null
    $candidatePaths = @(
        (Join-Path $env:ProgramFiles "WindowsPowerShell\Scripts\Get-WindowsAutopilotInfo.ps1"),
        (Join-Path ${env:ProgramFiles(x86)} "WindowsPowerShell\Scripts\Get-WindowsAutopilotInfo.ps1"),
        (Join-Path $HOME "Documents\WindowsPowerShell\Scripts\Get-WindowsAutopilotInfo.ps1")
    )
    foreach ($p in $candidatePaths) {
        if ($p -and (Test-Path $p)) { $scriptPath = $p; break }
    }
    if (-not $scriptPath) {
        $cmd = Get-Command Get-WindowsAutopilotInfo.ps1 -ErrorAction SilentlyContinue
        if ($cmd) { $scriptPath = $cmd.Source }
    }
    if (-not $scriptPath) {
        throw "Could not locate Get-WindowsAutopilotInfo.ps1 after install - checked standard AllUsers/CurrentUser script paths."
    }
    Write-Log "Using script at: $scriptPath"

    Write-Log "Uploading hardware hash to Intune - sign in when prompted..."
    $params = @{
        Online = $true
        Assign = $true   # auto-assigns default Autopilot profile if one is configured
    }
    if ($GroupTag) { $params["GroupTag"] = $GroupTag }

    & $scriptPath @params

    Write-Log "Upload completed successfully."

    if ($RestartAfter) {
        Write-Log "Restarting device in 10 seconds so it can re-check-in at OOBE..."
        Restart-Computer -Force -Delay 10
    }
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
