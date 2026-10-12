@echo off
setlocal
title RMutils Lite
set "SELF=%~f0"
mode con: cols=100
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF); iex $s.Substring($s.LastIndexOf('#PSBEGIN'))"
exit /b

#PSBEGIN
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$G = @{ Cancel = $false; Crumb = ''; Pending = ''; Freed = 0 }
$Root = Split-Path $env:SELF
$W = [Math]::Max(60, [Math]::Min(96, [Console]::WindowWidth - 2))

# ================= Infos de base =================
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$osName = (Get-CimInstance Win32_OperatingSystem).Caption -replace '^Microsoft ', ''
$pcInfo = "{0}  |  {1} {2} (build {3})" -f $env:COMPUTERNAME, $osName, $cv.DisplayVersion, $cv.CurrentBuild

$LogFile = Join-Path $Root ("RMutils_logs\{0}_lite_{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
try { New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null } catch {}

$banner = @'
   ____  __  __       _   _ _       _     _ _
  |  _ \|  \/  |_   _| |_(_) |___  | |   (_) |_ ___
  | |_) | |\/| | | | | __| | / __| | |   | | __/ _ \
  |  _ <| |  | | |_| | |_| | \__ \ | |___| | ||  __/
  |_| \_\_|  |_|\__,_|\__|_|_|___/ |_____|_|\__\___|
'@

# ================= Affichage =================
function Log($m) { try { Add-Content -Path $LogFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) -Encoding UTF8 } catch {} }

function Show-Header($crumb) {
    Clear-Host
    Write-Host ""
    Write-Host $banner -ForegroundColor Cyan
    Write-Host ("  " + $pcInfo) -ForegroundColor DarkGray
    Write-Host "  Mode Lite : sans droits administrateur" -ForegroundColor DarkYellow
    Write-Host ("  " + ('=' * ($W - 2))) -ForegroundColor DarkGray
    if ($crumb) { Write-Host ("  " + $crumb) -ForegroundColor White }
}

function Section($t) {
    Write-Host ""
    Write-Host "  >> $t" -ForegroundColor Cyan
    Write-Host ("  " + ('-' * ($W - 2))) -ForegroundColor DarkGray
    Log ">> $t"
}

function Fit($t, $n) {
    $t = [string]$t
    if ($t.Length -gt ($n - 2)) { $t = $t.Substring(0, $n - 5) + '...' }
    return ($t + ' ').PadRight($n, '.')
}

function Cut($t, $n) { $t = [string]$t; if ($t.Length -gt $n) { $t.Substring(0, $n - 3) + '...' } else { $t } }

function Step($label) { $G.Pending = $label; Write-Host ("  " + (Fit $label ($W - 20)) + " ") -NoNewline }
function Done($status, $color) { Write-Host $status -ForegroundColor $color; Log ("{0} : {1}" -f $G.Pending, $status) }

function Info($k, $v, $c = 'Gray') {
    Write-Host ("  {0,-20}: " -f $k) -NoNewline -ForegroundColor DarkGray
    Write-Host $v -ForegroundColor $c
    Log ("{0} : {1}" -f $k, $v)
}

function Note($t) { Write-Host ("  " + $t) -ForegroundColor DarkYellow; Log $t }

function Show-Tail($lines, $n = 2) {
    foreach ($l in @($lines | Select-Object -Last $n)) { Write-Host ("       " + $l) -ForegroundColor DarkGray; Log "   $l" }
}

function Fmt($b) {
    $b = [double]$b
    if ($b -ge 1GB) { "{0:N1} Go" -f ($b / 1GB) } elseif ($b -ge 1MB) { "{0:N0} Mo" -f ($b / 1MB) } else { "{0:N0} Ko" -f ($b / 1KB) }
}

function Row($k, $v, $c = 'Gray') { [pscustomobject]@{ K = $k; V = [string]$v; C = $c } }

function Show-Sections($secs) {
    foreach ($s in $secs) { Section $s.T; foreach ($r in $s.R) { Info $r.K $r.V $r.C } }
}

# ================= Menu fleches =================
function Show-Menu($crumb, $items, [ref]$sel) {
    Show-Header $crumb
    $top = [Console]::CursorTop
    [Console]::CursorVisible = $false
    while ($true) {
        [Console]::SetCursorPosition(0, $top)
        Write-Host ""
        $n = 0
        for ($i = 0; $i -lt $items.Count; $i++) {
            $it = $items[$i]
            if ($it.Back -or $it.Quit) { $num = '0' } else { $n++; $num = [string]$n }
            $txt = " {0}  {1}" -f $num, $it.Label
            if ($i -eq $sel.Value) {
                Write-Host "  " -NoNewline
                Write-Host (">" + $txt).PadRight(58) -ForegroundColor Black -BackgroundColor Cyan
            } else {
                Write-Host ("   " + $txt).PadRight(60)
            }
        }
        Write-Host ""
        Write-Host ("  " + ('-' * ($W - 2))) -ForegroundColor DarkGray
        $d = @($items[$sel.Value].Desc)
        for ($j = 0; $j -lt 7; $j++) {
            $line = if ($j -lt $d.Count) { "  " + $d[$j] } else { "" }
            Write-Host $line.PadRight($W) -ForegroundColor Gray
        }
        Write-Host ("  " + ('-' * ($W - 2))) -ForegroundColor DarkGray
        Write-Host ("  Fleches : naviguer   Entree : valider   1-9 : acces direct   Echap : retour").PadRight($W) -ForegroundColor DarkGray

        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            'UpArrow'   { $sel.Value = ($sel.Value - 1 + $items.Count) % $items.Count }
            'DownArrow' { $sel.Value = ($sel.Value + 1) % $items.Count }
            'Home'      { $sel.Value = 0 }
            'End'       { $sel.Value = $items.Count - 1 }
            'Enter'     { [Console]::CursorVisible = $true; return $sel.Value }
            'Escape'    { [Console]::CursorVisible = $true; return -1 }
            'Backspace' { [Console]::CursorVisible = $true; return -1 }
            default {
                $c = [string]$k.KeyChar
                if ($c -eq '0') {
                    for ($i = 0; $i -lt $items.Count; $i++) {
                        if ($items[$i].Back -or $items[$i].Quit) { $sel.Value = $i; [Console]::CursorVisible = $true; return $i }
                    }
                } elseif ($c -match '^[1-9]$') {
                    $want = [int]$c; $n = 0
                    for ($i = 0; $i -lt $items.Count; $i++) {
                        if ($items[$i].Back -or $items[$i].Quit) { continue }
                        $n++
                        if ($n -eq $want) { $sel.Value = $i; [Console]::CursorVisible = $true; return $i }
                    }
                }
            }
        }
    }
}

# ================= Utilitaires =================
function Run-Quiet($exe, $a) {
    $o = Join-Path $env:TEMP ("rmu_" + [guid]::NewGuid().ToString())
    $p = Start-Process -FilePath $exe -ArgumentList $a -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.e"
    Remove-Item $o, "$o.e" -Force -ErrorAction SilentlyContinue
    return $p.ExitCode
}

function Get-ExportDir {
    $d = Join-Path $Root ("RMutils_export\" + $env:COMPUTERNAME)
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

function Get-Winget { $c = Get-Command winget -ErrorAction SilentlyContinue; if ($c) { return $c.Source } }

function Ask-YesNo($q) {
    Write-Host ("  " + $q + " (O/N) ") -NoNewline -ForegroundColor White
    $k = [string][Console]::ReadKey($true).KeyChar
    Write-Host $k
    return ($k -match '^[oOyY]$')
}

# ================= Mises a jour =================
function Do-WUCheck {
    Section 'Windows Update'
    Step 'Recherche des mises a jour'
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $r = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
    } catch { Done 'ERREUR' Red; Show-Tail @($_.Exception.Message) 1; return }
    $n = $r.Updates.Count
    if ($n -eq 0) { Done 'A JOUR' Green; return }
    Done "$n en attente" Yellow
    foreach ($u in $r.Updates) { Write-Host ("     - " + (Cut $u.Title ($W - 8))); Log ("   - " + $u.Title) }
    Write-Host ""
    Note "L'installation demande les droits admin : RMutils complet, ou Windows Update."
    Write-Host ""
    if (Ask-YesNo 'Ouvrir Windows Update dans Parametres ?') { Start-Process 'ms-settings:windowsupdate' }
}

function Get-WingetUpgrades($wg) {
    $ErrorActionPreference = 'Continue'
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $raw = & $wg upgrade --accept-source-agreements --disable-interactivity 2>$null } finally { [Console]::OutputEncoding = $old }

    $lines = @(); foreach ($l in $raw) { $lines += ([string]$l -split "`r")[-1] }
    $sep = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{10,}') { $sep = $i; break } }
    if ($sep -lt 1) { return @() }

    $starts = @(0) + @([regex]::Matches($lines[$sep - 1], '\s+(?=\S)') | ForEach-Object { $_.Index + $_.Length })
    if ($starts.Count -lt 4) { return @() }

    $apps = @()
    for ($i = $sep + 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Length -le $starts[3]) { break }
        $col = { param($k) $e = if ($k + 1 -lt $starts.Count) { [Math]::Min($starts[$k + 1], $l.Length) } else { $l.Length }; $l.Substring($starts[$k], $e - $starts[$k]).Trim() }
        $apps += [pscustomobject]@{ Name = (& $col 0); Id = (& $col 1); Version = (& $col 2); Available = (& $col 3) }
    }
    return $apps
}

function Do-Apps {
    $t0 = Get-Date
    Section 'Applications (winget)'
    $wg = Get-Winget
    if (-not $wg) { Step 'winget'; Done 'ABSENT' Yellow; return }
    Step 'Recherche des mises a jour'
    $apps = @(Get-WingetUpgrades $wg)
    if ($apps.Count -eq 0) { Done 'A JOUR' Green; return }
    Done "$($apps.Count) trouvee(s)" Yellow
    Note "Une demande UAC peut apparaitre pour les applis installees pour tout le PC."
    $ok = 0; $ko = 0; $i = 0
    foreach ($a in $apps) {
        $i++
        Step ("[{0}/{1}] {2}  {3} -> {4}" -f $i, $apps.Count, $a.Name, $a.Version, $a.Available)
        if ($a.Id.EndsWith([string][char]0x2026)) { Done 'IGNORE' Yellow; $ko++; continue }
        $code = Run-Quiet $wg ("upgrade --id `"{0}`" --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity" -f $a.Id)
        if ($code -eq 0) { Done 'OK' Green; $ok++ } else { Done 'ECHEC' Red; $ko++ }
    }
    Section 'Resume'
    Info 'Applications' ("{0} mise(s) a jour, {1} echec(s)" -f $ok, $ko) $(if ($ko) { 'Yellow' } else { 'Green' })
    Info 'Duree' ("{0:hh\:mm\:ss}" -f ((Get-Date) - $t0))
}

# ================= Diagnostic =================
function Get-VolumeSection {
    $rows = @()
    foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object DeviceID)) {
        $pct = if ($v.Size) { [math]::Round(($v.Size - $v.FreeSpace) / $v.Size * 100) } else { 0 }
        $c = if ($pct -ge 90) { 'Red' } elseif ($pct -ge 75) { 'Yellow' } else { 'Green' }
        $rows += (Row ("Volume {0}" -f $v.DeviceID) ("{0} libres sur {1} ({2} % utilises)" -f (Fmt $v.FreeSpace), (Fmt $v.Size), $pct) $c)
    }
    @{ T = 'Stockage'; R = $rows }
}

function Get-SysSections {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bb = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $gpus = @(Get-CimInstance Win32_VideoController)
    $up = (Get-Date) - $os.LastBootUpTime

    $act = 'Inconnue'; $actC = 'Yellow'
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | Select-Object -First 1
        if ($lic.LicenseStatus -eq 1) { $act = 'Active'; $actC = 'Green' } else { $act = 'Non active'; $actC = 'Red' }
    } catch {}

    $ramTotal = ($ram | Measure-Object Capacity -Sum).Sum
    if (-not $ramTotal) { $ramTotal = $cs.TotalPhysicalMemory }
    $ramSpeed = ($ram | Select-Object -First 1).ConfiguredClockSpeed
    if (-not $ramSpeed) { $ramSpeed = ($ram | Select-Object -First 1).Speed }

    $sys = @(
        Row 'Nom du PC' $env:COMPUTERNAME
        Row 'Utilisateur' $env:USERNAME
        Row 'Modele' ("{0} {1}" -f $cs.Manufacturer, $cs.Model)
        Row 'N de serie' $bios.SerialNumber
        Row 'Windows' ("{0} {1} (build {2}.{3})" -f $osName, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR)
        Row 'Activation' $act $actC
        Row 'Allume depuis' ("{0} j {1} h {2} min" -f $up.Days, $up.Hours, $up.Minutes)
    )
    $hw = @(
        Row 'Processeur' ([string]$cpu.Name).Trim()
        Row 'Coeurs / threads' ("{0} / {1}" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
        Row 'Memoire' ("{0:N0} Go ({1} barrette(s), {2} MHz)" -f ($ramTotal / 1GB), $ram.Count, $ramSpeed)
    )
    foreach ($g in $gpus) { $hw += (Row 'Carte graphique' $g.Name) }
    $hw += (Row 'Carte mere' ("{0} {1}" -f $bb.Manufacturer, $bb.Product))
    $hw += (Row 'BIOS' ("{0} ({1:dd/MM/yyyy})" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate))

    @{ T = 'Systeme'; R = $sys }
    @{ T = 'Materiel'; R = $hw }
    Get-VolumeSection
}

function Get-DiskSections {
    $disks = @()
    try { $disks = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId) } catch {}
    if ($disks.Count -gt 0) {
        foreach ($d in $disks) {
            $h = [string]$d.HealthStatus
            $hc = switch ($h) { 'Healthy' { 'Green' } 'Warning' { 'Yellow' } default { 'Red' } }
            $ht = switch ($h) { 'Healthy' { 'Bon' } 'Warning' { 'Degrade' } 'Unhealthy' { 'Critique' } default { $h } }
            @{ T = ("Disque {0} - {1}" -f $d.DeviceId, $d.FriendlyName); R = @(
                Row 'Etat' $ht $hc
                Row 'Type' ("{0} ({1})" -f $d.MediaType, $d.BusType)
                Row 'Capacite' (Fmt $d.Size)
            ) }
        }
    } else {
        foreach ($d in @(Get-CimInstance Win32_DiskDrive | Sort-Object Index)) {
            $c = if ($d.Status -eq 'OK') { 'Green' } else { 'Red' }
            @{ T = ("Disque {0} - {1}" -f $d.Index, $d.Model); R = @(
                Row 'Etat' $d.Status $c
                Row 'Interface' $d.InterfaceType
                Row 'Capacite' (Fmt $d.Size)
            ) }
        }
    }
}

function Get-BatterySection {
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return }
    $rows = @( Row 'Charge' ("{0} %" -f $b.EstimatedChargeRemaining) )
    try {
        $des = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
        $full = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
        if ($des -and $full) {
            $hp = [math]::Min(100, [math]::Round($full / $des * 100))
            $rows += (Row "Capacite d'origine" ("{0:N0} mWh" -f $des))
            $rows += (Row 'Capacite actuelle' ("{0:N0} mWh" -f $full))
            $rows += (Row 'Sante' ("{0} % (usure {1} %)" -f $hp, (100 - $hp)) $(if ($hp -ge 80) { 'Green' } elseif ($hp -ge 60) { 'Yellow' } else { 'Red' }))
        }
    } catch {}
    @{ T = 'Batterie'; R = $rows }
}

function Get-NetSection {
    $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if (-not $cfg) { return @{ T = 'Reseau'; R = @(Row 'Connexion' 'Aucune carte connectee' 'Red') } }
    $dns = (@($cfg.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses) -join ', '
    @{ T = 'Reseau'; R = @(
        Row 'Interface' ("{0} ({1})" -f $cfg.InterfaceAlias, $cfg.NetAdapter.LinkSpeed)
        Row 'Adresse IP' ((@($cfg.IPv4Address).IPAddress) -join ', ')
        Row 'Passerelle' (@($cfg.IPv4DefaultGateway)[0].NextHop)
        Row 'DNS' $dns
        Row 'Adresse MAC' $cfg.NetAdapter.MacAddress
    ) }
}

function Get-HotfixSection {
    $rows = @()
    foreach ($h in @(Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 10)) {
        $rows += (Row $h.HotFixID ("{0} - {1:dd/MM/yyyy}" -f $h.Description, $h.InstalledOn))
    }
    @{ T = 'Dernieres mises a jour installees'; R = $rows }
}

function Do-SysInfo {
    Step 'Collecte des informations'
    $secs = @(Get-SysSections)
    Done 'OK' Green
    Show-Sections $secs
}

function Do-Disks {
    Step 'Lecture des disques'
    $secs = @(Get-DiskSections) + @(Get-VolumeSection)
    Done 'OK' Green
    Show-Sections $secs
    Write-Host ""
    Note "Temperature, usure et erreurs de lecture : version complete (admin)."
}

function Do-Battery {
    $sec = Get-BatterySection
    if (-not $sec) { Step 'Batterie'; Done 'AUCUNE (PC fixe ?)' Yellow; return }
    Show-Sections @($sec)
    Section 'Rapport detaille'
    $out = Join-Path (Get-ExportDir) ("batterie_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    Step 'Generation du rapport powercfg'
    if ((Run-Quiet 'powercfg.exe' "/batteryreport /output `"$out`"") -eq 0) { Done 'OK' Green; Info 'Fichier' $out } else { Done 'ECHEC' Red }
}

function Test-Ping($label, $target) {
    Step $label
    $p = @(Test-Connection $target -Count 2 -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) { Done ("OK ({0} ms)" -f [math]::Round(($p | Measure-Object ResponseTime -Average).Average)) Green }
    else { Done 'ECHEC' Red }
}

function Do-Network {
    $sec = Get-NetSection
    Show-Sections @($sec)
    Section 'Tests de connexion'
    $gw = ($sec.R | Where-Object K -eq 'Passerelle').V
    if ($gw) { Test-Ping 'Passerelle (box / routeur)' $gw }
    Test-Ping 'Internet (1.1.1.1)' '1.1.1.1'
    Step 'Resolution DNS (microsoft.com)'
    try { Resolve-DnsName microsoft.com -Type A -DnsOnly -ErrorAction Stop | Out-Null; Done 'OK' Green } catch { Done 'ECHEC' Red }
    Step 'Acces web'
    try { Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null; Done 'OK' Green } catch { Done 'ECHEC' Red }
}

function Do-Report {
    Step 'Collecte des informations'
    $secs = @(Get-SysSections) + @(Get-DiskSections) + @(Get-BatterySection) + @(Get-NetSection) + @(Get-HotfixSection)
    Done 'OK' Green

    Step 'Generation du rapport HTML'
    $cls = @{ Green = 'ok'; Yellow = 'warn'; Red = 'bad' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($s in $secs) {
        [void]$sb.Append("<h2>" + [Net.WebUtility]::HtmlEncode($s.T) + "</h2><table>")
        foreach ($r in $s.R) {
            [void]$sb.Append("<tr><th>" + [Net.WebUtility]::HtmlEncode($r.K) + "</th><td class='" + $cls[$r.C] + "'>" + [Net.WebUtility]::HtmlEncode($r.V) + "</td></tr>")
        }
        [void]$sb.Append("</table>")
    }
    $css = "body{font-family:Segoe UI,Arial,sans-serif;max-width:900px;margin:2rem auto;padding:0 1rem;color:#222}h1{font-weight:600}.sub{color:#777;margin-top:-.5rem}h2{font-size:1.1rem;border-bottom:1px solid #ddd;padding-bottom:4px;margin-top:2rem}table{border-collapse:collapse;width:100%}th{text-align:left;width:230px;color:#666;font-weight:normal;padding:4px 8px}td{padding:4px 8px}.ok{color:#1a7f37}.warn{color:#b58100}.bad{color:#c62828;font-weight:bold}"
    $html = "<!DOCTYPE html><html lang='fr'><head><meta charset='utf-8'><title>Rapport $env:COMPUTERNAME</title><style>$css</style></head><body><h1>Rapport RMutils Lite - $env:COMPUTERNAME</h1><p class='sub'>Genere le $(Get-Date -Format 'dd/MM/yyyy HH:mm') (sans droits admin)</p>$($sb.ToString())</body></html>"
    $f = Join-Path (Get-ExportDir) ("rapport_lite_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    [IO.File]::WriteAllText($f, $html, [Text.Encoding]::UTF8)
    Done 'OK' Green
    Info 'Fichier' $f
}

# ================= Nettoyage =================
function Get-Size($p, $f = '*') { [double](Get-ChildItem $p -Recurse -File -Force -Filter $f -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }

function Clean-Path($label, $path, $filter = '*') {
    Step $label
    if (-not (Test-Path $path)) { Done 'RIEN' DarkGray; return }
    $b = Get-Size $path $filter
    Get-ChildItem $path -Filter $filter -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $f = [math]::Max(0, $b - (Get-Size $path $filter))
    $G.Freed += $f
    Done (Fmt $f) $(if ($f -gt 0) { 'Green' } else { 'DarkGray' })
}

function Clean-Glob($label, $patterns) {
    Step $label
    $paths = @(foreach ($p in $patterns) { Resolve-Path $p -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath } })
    if ($paths.Count -eq 0) { Done 'ABSENT' DarkGray; return }
    $b = 0; foreach ($p in $paths) { $b += Get-Size $p }
    foreach ($p in $paths) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } }
    $a = 0; foreach ($p in $paths) { $a += Get-Size $p }
    $f = [math]::Max(0, $b - $a)
    $G.Freed += $f
    Done (Fmt $f) $(if ($f -gt 0) { 'Green' } else { 'DarkGray' })
}

function Do-Clean {
    $G.Freed = 0
    Clean-Path 'Fichiers temporaires' $env:TEMP
    Clean-Path 'Miniatures' "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" 'thumbcache_*.db'
    Clean-Path "Rapports d'erreurs" "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
    Clean-Path 'Dumps de plantage' "$env:LOCALAPPDATA\CrashDumps"
    Step 'Corbeille'
    try { Clear-RecycleBin -Force -ErrorAction Stop } catch {}
    Done 'VIDEE' Green
    Section 'Resume'
    Info 'Espace libere' (Fmt $G.Freed) Green
}

function Do-BrowserClean {
    $open = @(Get-Process chrome, msedge, firefox -ErrorAction SilentlyContinue)
    if ($open.Count -gt 0) {
        Note "Des navigateurs sont ouverts : leur cache ne sera nettoye qu'en partie."
        if (-not (Ask-YesNo 'Continuer quand meme ?')) { return }
        Write-Host ""
    }
    $G.Freed = 0
    $ch = "$env:LOCALAPPDATA\Google\Chrome\User Data\*"
    $ed = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*"
    Clean-Glob 'Google Chrome' @("$ch\Cache", "$ch\Code Cache", "$ch\GPUCache")
    Clean-Glob 'Microsoft Edge' @("$ed\Cache", "$ed\Code Cache", "$ed\GPUCache")
    Clean-Glob 'Mozilla Firefox' @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2")
    Section 'Resume'
    Info 'Espace libere' (Fmt $G.Freed) Green
}

# ================= Reparation =================
function Do-FlushDns {
    Step 'Vidage du cache DNS'
    if ((Run-Quiet 'ipconfig.exe' '/flushdns') -eq 0) { Done 'OK' Green } else { Done 'ECHEC' Red }
}

function Stop-Explorer {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Start-Explorer {
    Start-Sleep -Seconds 1
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

function Do-RestartExplorer {
    Step "Arret de l'Explorateur"; Stop-Explorer; Done 'OK' Green
    Step "Relance de l'Explorateur"; Start-Explorer; Done 'OK' Green
}

function Do-IconCache {
    $G.Freed = 0
    Step "Arret de l'Explorateur"; Stop-Explorer; Done 'OK' Green
    Clean-Path 'Cache des icones' "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" 'iconcache_*.db'
    Clean-Path 'Cache des miniatures' "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" 'thumbcache_*.db'
    Step 'Ancien cache des icones'
    $old = Join-Path $env:LOCALAPPDATA 'IconCache.db'
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue; Done 'OK' Green } else { Done 'RIEN' DarkGray }
    Step "Relance de l'Explorateur"; Start-Explorer; Done 'OK' Green
}

function Do-StoreReset {
    Step 'Reinitialisation du cache du Microsoft Store'
    try { Start-Process wsreset.exe -Wait -ErrorAction Stop; Done 'OK' Green } catch { Done 'ECHEC' Red }
    Note "Le Store s'ouvre tout seul a la fin : c'est normal."
}

# ================= Wi-Fi =================
function Pick-Source($sub) {
    $base = Join-Path $Root 'RMutils_export'
    $dirs = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { @(Get-ChildItem (Join-Path $_.FullName $sub) -ErrorAction SilentlyContinue).Count -gt 0 })
    if ($dirs.Count -eq 0) { Step 'Recherche des sauvegardes sur la cle'; Done 'AUCUNE' Yellow; return $null }
    $items = @($dirs | ForEach-Object {
        $p = Join-Path $_.FullName $sub
        @{ Label = $_.Name; Desc = @(("Sauvegarde du PC " + $_.Name), ("Dossier : " + $p), ("Modifiee le " + (Get-Item $p).LastWriteTime.ToString('dd/MM/yyyy HH:mm'))) }
    })
    $items += @{ Label = 'Annuler'; Desc = @('Revenir au menu sans rien restaurer.'); Back = $true }
    $s = 0
    $r = Show-Menu ($G.Crumb + ' > Choisir la sauvegarde') $items ([ref]$s)
    if ($r -lt 0 -or $items[$r].Back) { $G.Cancel = $true; return $null }
    Show-Header $G.Crumb
    return $dirs[$r].FullName
}

function Do-RestoreWifi {
    $src = Pick-Source 'wifi'
    if (-not $src) { return }
    foreach ($f in @(Get-ChildItem (Join-Path $src 'wifi') -Filter *.xml)) {
        $name = $f.BaseName
        try { $name = ([xml](Get-Content $f.FullName -Raw)).WLANProfile.name } catch {}
        Step "Reseau $name"
        if ((Run-Quiet 'netsh.exe' "wlan add profile filename=`"$($f.FullName)`" user=current") -eq 0) { Done 'OK' Green } else { Done 'ECHEC' Red }
    }
}

function Do-ListWifi {
    Section 'Reseaux Wi-Fi enregistres'
    $ErrorActionPreference = 'Continue'
    $raw = netsh.exe wlan show profiles 2>$null
    $names = @($raw | Where-Object { $_ -match '^\s+.+:\s+\S' -and $_ -notmatch '^\s+-' } | ForEach-Object { ($_ -split ':\s+', 2)[1].Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) { Note 'Aucun reseau enregistre (ou pas de carte Wi-Fi).'; return }
    foreach ($n in $names) { Write-Host ("     - " + $n); Log ("   - " + $n) }
}

# ================= Installation =================
$AppsFile = Join-Path $Root 'RMutils_apps.txt'

function Ensure-AppsFile {
    if (Test-Path $AppsFile) { return }
    $default = @(
        "# RMutils - pack d'applications : un identifiant winget par ligne",
        "# Trouver un identifiant : winget search <nom>   (les lignes # sont ignorees)",
        "Mozilla.Firefox",
        "7zip.7zip",
        "VideoLAN.VLC",
        "Notepad++.Notepad++",
        "Adobe.Acrobat.Reader.64-bit"
    )
    Set-Content -Path $AppsFile -Value $default -Encoding ASCII
}

function Do-AppPack {
    $wg = Get-Winget
    if (-not $wg) { Step 'winget'; Done 'ABSENT' Yellow; return }
    Ensure-AppsFile
    $ids = @(Get-Content $AppsFile | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ })
    if ($ids.Count -eq 0) { Step 'Liste des applications'; Done 'VIDE' Yellow; return }
    Note "Une demande UAC peut apparaitre pour certaines applis : accepte-la pour continuer."
    $i = 0
    foreach ($id in $ids) {
        $i++
        Step ("[{0}/{1}] {2}" -f $i, $ids.Count, $id)
        if ((Run-Quiet $wg "list --id `"$id`" --exact --accept-source-agreements --disable-interactivity") -eq 0) { Done 'DEJA INSTALLE' DarkGray; continue }
        if ((Run-Quiet $wg "install --id `"$id`" --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity") -eq 0) { Done 'INSTALLE' Green }
        else { Done 'ECHEC' Red }
    }
}

function Do-EditApps { Ensure-AppsFile; Start-Process notepad.exe -ArgumentList "`"$AppsFile`"" }

# ================= Definition des menus =================
$back = @{ Label = 'Retour'; Desc = @('Revenir au menu principal.'); Back = $true }

$menuMaj = @(
    @{ Label = 'Verifier les MAJ Windows'; Run = { Do-WUCheck }; Desc = @(
        "Liste les mises a jour Windows en attente (securite, cumulatives, pilotes...).",
        "L'installation demande les droits admin : propose ensuite d'ouvrir",
        "Windows Update dans Parametres. Pour tout installer d'un coup : RMutils complet.") }
    @{ Label = 'Mettre a jour les applications'; Run = { Do-Apps }; Desc = @(
        "Met a jour en silencieux les applis connues de winget.",
        "Applis installees pour ton compte seulement : aucune question.",
        "Applis installees pour tout le PC : une demande UAC peut apparaitre.",
        "Si tu la refuses, l'appli est simplement marquee ECHEC.",
        "Ferme les applis avant. Duree : 1 a 10 min.") }
    @{ Label = 'Ouvrir Windows Update'; NoPause = $true; Run = { Start-Process 'ms-settings:windowsupdate' }; Desc = @(
        "Ouvre la page Windows Update des Parametres.",
        "Windows gere lui-meme le telechargement et l'installation.") }
    $back
)

$menuDiag = @(
    @{ Label = 'Infos systeme'; Run = { Do-SysInfo }; Desc = @(
        "Resume du PC : modele, n de serie, version et activation de Windows, uptime,",
        "processeur, memoire, carte graphique, carte mere, BIOS et espace disque.",
        "Lecture seule, rien n'est modifie.") }
    @{ Label = 'Sante des disques'; Run = { Do-Disks }; Desc = @(
        "Etat general, type et capacite de chaque disque, puis remplissage des volumes.",
        "Sans admin, Windows ne donne pas acces a la temperature, a l'usure",
        "ni aux erreurs de lecture : pour ca, utilise RMutils complet.") }
    @{ Label = 'Etat de la batterie'; Run = { Do-Battery }; Desc = @(
        "Portables uniquement. Charge actuelle et, si Windows le permet, usure reelle.",
        "Genere aussi le rapport detaille Windows (powercfg) dans RMutils_export sur la cle :",
        "il contient toujours la capacite d'origine et la capacite actuelle.") }
    @{ Label = 'Diagnostic reseau'; Run = { Do-Network }; Desc = @(
        "Affiche IP, passerelle, DNS et MAC, puis teste dans l'ordre :",
        "box, Internet, resolution DNS, acces web.",
        "Le premier test en echec indique ou ca coince :",
        "box KO = cable / Wi-Fi, Internet KO = box / FAI, DNS KO = serveur DNS.") }
    @{ Label = 'Rapport HTML complet'; Run = { Do-Report }; Desc = @(
        "Genere un rapport HTML (systeme, disques, batterie, reseau, 10 dernieres MAJ)",
        "dans RMutils_export\<nom du PC>\ sur la cle.") }
    $back
)

$menuClean = @(
    @{ Label = 'Nettoyage rapide'; Run = { Do-Clean }; Desc = @(
        "Supprime les fichiers de ton compte : temporaires, miniatures, rapports d'erreurs,",
        "dumps de plantage. Vide aussi la corbeille.",
        "Les fichiers en cours d'utilisation sont ignores. Affiche l'espace libere.",
        "Temp Windows et cache Windows Update : version complete (admin).") }
    @{ Label = 'Caches des navigateurs'; Run = { Do-BrowserClean }; Desc = @(
        "Vide le cache de Chrome, Edge et Firefox (tous les profils).",
        "Historique, cookies, mots de passe et onglets ne sont PAS touches.",
        "Ferme les navigateurs avant pour un nettoyage complet.",
        "Les sites seront un peu plus lents au premier chargement.") }
    $back
)

$menuRepair = @(
    @{ Label = 'Vider le cache DNS'; Run = { Do-FlushDns }; Desc = @(
        "Oublie les adresses de sites memorisees par Windows.",
        "Utile quand un site ne s'ouvre plus alors qu'il marche sur un autre appareil,",
        "ou apres un changement de box / DNS. Sans risque.") }
    @{ Label = "Redemarrer l'Explorateur"; Run = { Do-RestartExplorer }; Desc = @(
        "Relance la barre des taches, le menu Demarrer et l'Explorateur de fichiers.",
        "Regle une barre des taches figee, un menu Demarrer qui ne s'ouvre plus,",
        "des icones du bureau qui ne repondent plus.",
        "Les fenetres de l'Explorateur ouvertes seront fermees.") }
    @{ Label = 'Reconstruire le cache des icones'; Run = { Do-IconCache }; Desc = @(
        "Supprime le cache des icones et des miniatures, puis relance l'Explorateur.",
        "A utiliser quand des icones sont blanches, fausses ou que les apercus",
        "d'images sont incorrects. L'ecran clignote quelques secondes, c'est normal.") }
    @{ Label = 'Reinitialiser le Microsoft Store'; Run = { Do-StoreReset }; Desc = @(
        "Lance wsreset : vide le cache du Microsoft Store.",
        "A utiliser si le Store ne s'ouvre plus ou si les telechargements bloquent.",
        "Le Store s'ouvre automatiquement a la fin.") }
    $back
)

$menuWifi = @(
    @{ Label = 'Lister les reseaux enregistres'; Run = { Do-ListWifi }; Desc = @(
        "Affiche les reseaux Wi-Fi memorises sur ce PC.",
        "Les mots de passe ne sont visibles qu'avec la version complete (admin).") }
    @{ Label = 'Restaurer des profils Wi-Fi'; Run = { Do-RestoreWifi }; Desc = @(
        "Choisis une sauvegarde sur la cle (faite avec RMutils complet)",
        "et reimporte ses reseaux Wi-Fi pour ton compte.",
        "Le PC se reconnectera tout seul aux reseaux connus.") }
    $back
)

$menuInstall = @(
    @{ Label = "Installer le pack d'applications"; Run = { Do-AppPack }; Desc = @(
        "Installe en silencieux les applis listees dans RMutils_apps.txt (racine de la cle).",
        "Liste par defaut creee au 1er lancement : Firefox, 7-Zip, VLC, Notepad++, Acrobat Reader.",
        "Les applis deja presentes sont ignorees.",
        "Une demande UAC peut apparaitre pour certaines applis.") }
    @{ Label = 'Modifier la liste des applications'; Run = { Do-EditApps }; NoPause = $true; Desc = @(
        "Ouvre RMutils_apps.txt dans le Bloc-notes.",
        "Un identifiant winget par ligne. Pour en trouver un : winget search <nom>",
        "Liste partagee avec RMutils complet.") }
    $back
)

$main = @(
    @{ Label = 'Mises a jour'; Items = $menuMaj; Sel = 0; Desc = @(
        "Verification des MAJ Windows et mise a jour des applications (winget).",
        "L'installation des MAJ Windows se fait via Parametres ou RMutils complet.") }
    @{ Label = 'Diagnostic'; Items = $menuDiag; Sel = 0; Desc = @(
        "Infos systeme, disques, batterie, diagnostic reseau et rapport HTML.",
        "Lecture seule : rien n'est modifie sur le PC.") }
    @{ Label = 'Nettoyage'; Items = $menuClean; Sel = 0; Desc = @(
        "Fichiers temporaires de ton compte, corbeille et caches des navigateurs.") }
    @{ Label = 'Reparation'; Items = $menuRepair; Sel = 0; Desc = @(
        "Petites reparations sans admin : cache DNS, Explorateur,",
        "cache des icones, Microsoft Store.",
        "SFC, DISM, reset Windows Update / reseau : version complete.") }
    @{ Label = 'Wi-Fi'; Items = $menuWifi; Sel = 0; Desc = @(
        "Liste des reseaux enregistres et restauration de profils depuis la cle.",
        "L'export avec mots de passe necessite la version complete.") }
    @{ Label = 'Installation'; Items = $menuInstall; Sel = 0; Desc = @(
        "Installation silencieuse d'un pack d'applications via winget.") }
    @{ Label = 'Quitter'; Quit = $true; Desc = @(
        "Ferme RMutils Lite.",
        "Le log de la session reste dans RMutils_logs sur la cle.") }
)

function Finish {
    Write-Host ""
    Write-Host "  Appuie sur une touche pour revenir au menu..." -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

# ================= Boucle principale =================
Log "=== RMutils Lite demarre sur $pcInfo (utilisateur $env:USERNAME) ==="
$selMain = 0
while ($true) {
    $r = Show-Menu 'Menu principal' $main ([ref]$selMain)
    if ($r -lt 0 -or $main[$r].Quit) { break }
    $cat = $main[$r]
    while ($true) {
        $s = $cat.Sel
        $r2 = Show-Menu ("Menu principal > " + $cat.Label) $cat.Items ([ref]$s)
        $cat.Sel = $s
        if ($r2 -lt 0) { break }
        $it = $cat.Items[$r2]
        if ($it.Back) { break }

        $G.Crumb = "Menu principal > {0} > {1}" -f $cat.Label, $it.Label
        $G.Cancel = $false
        Show-Header $G.Crumb
        Log "=== $($G.Crumb) ==="
        try { & $it.Run }
        catch {
            Write-Host ""
            Write-Host ("  ERREUR : " + $_.Exception.Message) -ForegroundColor Red
            Log ("ERREUR : " + $_.Exception.Message)
        }
        [Console]::CursorVisible = $true
        if (-not $G.Cancel -and -not $it.NoPause) { Finish }
    }
}
Log "=== Fin de session ==="
Clear-Host
