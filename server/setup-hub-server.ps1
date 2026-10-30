<#
  Hub server setup for an always-on Windows laptop.

  What it does (each step asks first):
    1. Keeps the laptop awake on power and when the lid is closed.
    2. Installs Tailscale, so your phone reaches the laptop privately from anywhere.
    3. Installs Proton Mail Bridge and makes it reachable from your phone over Tailscale only.
    4. Opens Hub's sync port to your Tailscale devices and starts Hub with Windows.

  Run it from PowerShell as Administrator:
    Set-ExecutionPolicy -Scope Process Bypass
    .\setup-hub-server.ps1
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

function Ask($question) {
  $answer = Read-Host "$question [Y/n]"
  return ($answer -eq '' -or $answer -match '^[Yy]')
}

function Has-Winget { return [bool](Get-Command winget -ErrorAction SilentlyContinue) }

Write-Host "`nHub server setup`n" -ForegroundColor Green

# 1. Power settings
if (Ask 'Keep the laptop awake when plugged in and when the lid is closed?') {
  powercfg /change standby-timeout-ac 0
  powercfg /change hibernate-timeout-ac 0
  powercfg /change monitor-timeout-ac 10
  # Lid close action on AC: 0 = do nothing.
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
  Write-Host '  Done. The screen still turns off after 10 minutes to save power.'
}

# 2. Tailscale
if (Ask 'Install Tailscale (private network between your phone and this laptop)?') {
  if (-not (Has-Winget)) { throw 'winget is missing. Install "App Installer" from the Microsoft Store, then run this again.' }
  winget install --id Tailscale.Tailscale -e --accept-source-agreements --accept-package-agreements
  Write-Host '  Open Tailscale from the Start menu and sign in. Install the Tailscale app on your phone with the same account.'
  Read-Host '  Press Enter once this laptop shows as connected in Tailscale'
}

$tailscaleExe = 'C:\Program Files\Tailscale\tailscale.exe'
$tsIp = $null
if (Test-Path $tailscaleExe) {
  $tsIp = (& $tailscaleExe ip -4 2>$null | Select-Object -First 1)
}
if ($tsIp) { Write-Host "  This laptop's Tailscale address: $tsIp" -ForegroundColor Cyan }

# 3. Proton Mail Bridge
if (Ask 'Install Proton Mail Bridge and share it with your phone over Tailscale?') {
  if (-not (Has-Winget)) { throw 'winget is missing.' }
  winget install --id Proton.ProtonMailBridge -e --accept-source-agreements --accept-package-agreements
  Write-Host '  Open Proton Mail Bridge, sign in, and turn on "Start Bridge on startup".'
  Read-Host '  Press Enter when Bridge is signed in'

  if (-not $tsIp) { $tsIp = Read-Host '  Tailscale address of this laptop (starts with 100.)' }

  # Bridge only listens on 127.0.0.1. Forward the Tailscale address to it.
  foreach ($port in 1143, 1025) {
    netsh interface portproxy delete v4tov4 listenaddress=$tsIp listenport=$port 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$tsIp listenport=$port connectaddress=127.0.0.1 connectport=$port | Out-Null
  }
  # Allow only Tailscale devices (100.64.0.0/10) to reach those ports.
  Get-NetFirewallRule -DisplayName 'Hub - Proton Bridge' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'Hub - Proton Bridge' -Direction Inbound -Protocol TCP -LocalPort 1143,1025 `
    -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null
  # portproxy needs the IP Helper service.
  Set-Service iphlpsvc -StartupType Automatic
  Start-Service iphlpsvc

  Write-Host "`n  In Hub on your phone: Mail -> Add account -> Proton Mail -> Server settings" -ForegroundColor Cyan
  Write-Host "  IMAP server $tsIp port 1143, SMTP server $tsIp port 1025," -ForegroundColor Cyan
  Write-Host "  with the username and password Bridge shows for your account." -ForegroundColor Cyan
}

# 4. Hub sync server
if (Ask 'Let your phone sync with Hub on this laptop (port 8787, Tailscale only)?') {
  Get-NetFirewallRule -DisplayName 'Hub - Sync' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'Hub - Sync' -Direction Inbound -Protocol TCP -LocalPort 8787 `
    -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null
  $hubExe = Read-Host '  Full path to hub.exe (from the unzipped Hub-windows.zip), or leave empty to skip autostart'
  if ($hubExe -and (Test-Path $hubExe)) {
    $startup = [Environment]::GetFolderPath('Startup')
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path $startup 'Hub.lnk'))
    $link.TargetPath = $hubExe
    $link.WorkingDirectory = Split-Path $hubExe
    $link.Save()
    Write-Host '  Hub now starts when you sign in to Windows.'
  }
  Write-Host '  In Hub on this laptop: Me -> Sync -> "Server". It shows the address and key for your phone.' -ForegroundColor Cyan
}

Write-Host "`nAll set.`n" -ForegroundColor Green
