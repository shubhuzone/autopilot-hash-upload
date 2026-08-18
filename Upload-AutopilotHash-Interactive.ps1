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
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null

function Write-Log { param($msg) Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Ensuring NuGet provider..."
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    Write-Log "Ensuring Get-WindowsAutopilotInfo script..."
    if (-not (Get-InstalledScript -Name Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue)) {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -Scope AllUsers -Confirm:$false
    }

    if (-not (Get-Module -ListAvailable -Name WindowsAutopilotIntune)) {
        Install-Module -Name WindowsAutopilotIntune -Force -Scope AllUsers -AllowClobber -Confirm:$false
    }

    $scriptPath = (Get-InstalledScript -Name Get-WindowsAutopilotInfo).Path

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
