# Bioreaktor-Labor: Fernzugriff einrichten (Tailscale + OpenSSH, nur Schluessel-Login)
# Aufruf in einer Administrator-PowerShell:
#   irm https://st.tim-arnold.de/lab.ps1 | iex

$PubKey  = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJwJfBxBF9nDnC/Syqa+fse4Ijq4DUaY/SA+IiTYExjH claude-bioreaktor-lab'
$TsExe   = 'C:\Program Files\Tailscale\tailscale.exe'
$TsName  = 'bioreaktor-lab'

function Step($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not $admin) {
    Write-Host 'Bitte PowerShell als Administrator starten (Rechtsklick -> Als Administrator ausfuehren).' -ForegroundColor Red
} else {

# --- 1. Tailscale ----------------------------------------------------------
Step 'Tailscale'
if (-not (Test-Path $TsExe)) {
    $msi = Join-Path $env:TEMP 'tailscale.msi'
    Write-Host 'Lade Tailscale herunter ...'
    Invoke-WebRequest 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi -UseBasicParsing
    Write-Host 'Installiere ...'
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
    for ($i = 0; $i -lt 30 -and -not (Test-Path $TsExe); $i++) { Start-Sleep 1 }
}
for ($i = 0; $i -lt 30 -and (Get-Service Tailscale -ErrorAction SilentlyContinue).Status -ne 'Running'; $i++) { Start-Sleep 1 }
$TsIp = & $TsExe ip -4 2>$null | Select-Object -First 1
if (-not $TsIp) {
    Write-Host 'Gleich erscheint ein Login-Link (oder der Browser oeffnet sich).' -ForegroundColor Yellow
    Write-Host 'Mit dem Account timarnoldev anmelden, dann geht es hier weiter.' -ForegroundColor Yellow
    & $TsExe up --hostname $TsName
    $TsIp = & $TsExe ip -4 2>$null | Select-Object -First 1
}

# --- 2. OpenSSH-Server -------------------------------------------------------
Step 'OpenSSH-Server (kann ein paar Minuten dauern)'
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
Start-Service sshd -ErrorAction Stop
Set-Service sshd -StartupType Manual   # startet nach Neustart NICHT automatisch
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
}

# Schluessel eintragen (Admin-Konten nutzen unter Windows eine zentrale Datei)
$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
if (-not (Test-Path $f) -or -not (Select-String -Path $f -SimpleMatch $PubKey -Quiet)) {
    Add-Content -Path $f -Value $PubKey -Encoding ascii
}
icacls $f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# --- 3. Netzwerk-Infos sammeln ---------------------------------------------
Step 'Sammle Netzwerk-Infos'
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
    ForEach-Object { "$($_.InterfaceAlias): $($_.IPAddress)/$($_.PrefixLength)" }
$neighbors = Get-NetNeighbor -AddressFamily IPv4 -State Reachable,Stale,Permanent -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notmatch '^(224\.|239\.|255\.)' -and $_.IPAddress -notlike '*.255' } |
    Select-Object -ExpandProperty IPAddress -Unique

function Test-Port($h, $p) {
    $c = New-Object Net.Sockets.TcpClient
    try { return $c.ConnectAsync($h, $p).Wait(300) -and $c.Connected } catch { return $false } finally { $c.Close() }
}
$open = foreach ($n in $neighbors) {
    $ports = @(80, 443, 4840, 4841, 8080) | Where-Object { Test-Port $n $_ }
    if ($ports) { "$n -> offen: $($ports -join ', ')" }
}
$eve = Get-Process | Where-Object { $_.Name -match 'eve|infors|iris' } | Select-Object -ExpandProperty Name -Unique

$summary = @"
--- Bioreaktor-Labor ---
Benutzer:      $(whoami)
Rechner:       $env:COMPUTERNAME
Tailscale-IP:  $TsIp
Netzwerke:
  $($ips -join "`n  ")
Geraete mit offenen Ports:
  $(if ($open) { $open -join "`n  " } else { '(keine gefunden)' })
eve/Infors-Prozesse: $(if ($eve) { $eve -join ', ' } else { '(keine)' })
"@

Write-Host "`n$summary" -ForegroundColor Green
Set-Clipboard -Value $summary
Write-Host "`nFertig. Die Zusammenfassung ist in der Zwischenablage - einfach an Claude schicken." -ForegroundColor Green
Write-Host 'Zum Abschalten spaeter:  irm https://st.tim-arnold.de/off.ps1 | iex' -ForegroundColor DarkGray
}
