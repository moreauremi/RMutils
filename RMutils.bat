@echo off
setlocal
title RMutils
set "SELF=%~f0"

:: Auto-elevation en administrateur
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

mode con: cols=100
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF); iex $s.Substring($s.LastIndexOf('#PSBEGIN'))"
exit /b

#PSBEGIN
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$G = @{ AutoReboot = $false; NeedReboot = $false; RebootAsk = $false; Cancel = $false; Crumb = ''; Pending = ''; Freed = 0 }
$Root = Split-Path $env:SELF
$W = [Math]::Max(60, [Math]::Min(96, [Console]::WindowWidth - 2))

# ================= Infos de base =================
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$osName = (Get-CimInstance Win32_OperatingSystem).Caption -replace '^Microsoft ', ''
$pcInfo = "{0}  |  {1} {2} (build {3})" -f $env:COMPUTERNAME, $osName, $cv.DisplayVersion, $cv.CurrentBuild

$LogFile = Join-Path $Root ("RMutils_logs\{0}_{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
try { New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null } catch {}

$banner = @'
   ____  __  __       _   _ _
  |  _ \|  \/  |_   _| |_(_) |___
  | |_) | |\/| | | | | __| | / __|
  |  _ <| |  | | |_| | |_| | \__ \
  |_| \_\_|  |_|\__,_|\__|_|_|___/
'@

# ================= Affichage =================
function Log($m) { try { Add-Content -Path $LogFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) -Encoding UTF8 } catch {} }

function Show-Header($crumb) {
    Clear-Host
    Write-Host ""
    Write-Host $banner -ForegroundColor Cyan
    Write-Host ("  " + $pcInfo) -ForegroundColor DarkGray
    if ($G.NeedReboot) { Write-Host "  /!\ Redemarrage en attente" -ForegroundColor Magenta }
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

function Step($label) { $G.Pending = $label; Write-Host ("  " + (Fit $label ($W - 20)) + " ") -NoNewline }
function Done($status, $color) { Write-Host $status -ForegroundColor $color; Log ("{0} : {1}" -f $G.Pending, $status) }

function Info($k, $v, $c = 'Gray') {
    Write-Host ("  {0,-20}: " -f $k) -NoNewline -ForegroundColor DarkGray
    Write-Host $v -ForegroundColor $c
    Log ("{0} : {1}" -f $k, $v)
}

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

function Label-Of($it) { if ($it.Label -is [scriptblock]) { & $it.Label } else { $it.Label } }

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
            $txt = " {0}  {1}" -f $num, (Label-Of $it)
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

function Run-Long($label, $exe, $a, $enc) {
    Step $label
    $x = [Console]::CursorLeft; $y = [Console]::CursorTop
    $o = Join-Path $env:TEMP ("rmu_" + [guid]::NewGuid().ToString())
    $p = Start-Process -FilePath $exe -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.e"
    $null = $p.Handle
    $t0 = Get-Date; $spin = '|/-\'; $i = 0
    [Console]::CursorVisible = $false
    while (-not $p.HasExited) {
        [Console]::SetCursorPosition($x, $y)
        Write-Host ("{0} en cours {1:hh\:mm\:ss}" -f $spin[$i % 4], ((Get-Date) - $t0)) -NoNewline -ForegroundColor DarkGray
        $i++; Start-Sleep -Milliseconds 250
    }
    $p.WaitForExit()
    [Console]::SetCursorPosition($x, $y); Write-Host (' ' * 22) -NoNewline; [Console]::SetCursorPosition($x, $y)
    [Console]::CursorVisible = $true
    $lines = @()
    try {
        $txt = Get-Content $o -Raw -Encoding $enc
        $lines = @($txt -split "[`r`n]+" | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -and $_ -notmatch '\d+([.,]\d+)?\s?%' -and $_ -notmatch '^[\[=]' })
    } catch {}
    Remove-Item $o, "$o.e" -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Code = $p.ExitCode; Lines = $lines }
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

function Ask-Reboot {
    Write-Host ""
    Write-Host "  /!\ Redemarrage necessaire pour terminer." -ForegroundColor Magenta
    if ($G.AutoReboot) {
        shutdown.exe /r /t 60 /c "RMutils : redemarrage (annuler : shutdown /a)"
        Write-Host "  Redemarrage dans 60 secondes (annuler : shutdown /a)." -ForegroundColor Magenta
        return
    }
    if (Ask-YesNo 'Redemarrer maintenant ?') {
        shutdown.exe /r /t 5
        Write-Host "  Redemarrage dans 5 secondes..." -ForegroundColor Magenta
    }
}

function Need-Reboot { $G.NeedReboot = $true; $G.RebootAsk = $true }

function New-RP($desc) {
    Step 'Point de restauration'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $old = (Get-ItemProperty $key -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-ItemProperty $key -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction Stop
        try { Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue }
        finally {
            if ($null -eq $old) { Remove-ItemProperty $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
            else { Set-ItemProperty $key -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction SilentlyContinue }
        }
        Done 'OK' Green
    } catch { Done 'ECHEC (on continue)' Yellow }
}

# ================= Mises a jour =================
function Invoke-WU($s) {
    Section 'Windows Update'
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'RMutils'
    for ($pass = 1; $pass -le 3; $pass++) {
        Step 'Recherche des mises a jour'
        try { $r = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0") }
        catch { Done 'ERREUR' Red; Show-Tail @($_.Exception.Message) 1; return }
        $list = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $r.Updates) {
            if ($u.InstallationBehavior.CanRequestUserInput) { continue }
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$list.Add($u)
        }
        if ($list.Count -eq 0) { Done 'A JOUR' Green; return }
        Done "$($list.Count) trouvee(s)" Yellow

        Step 'Telechargement'
        try { $d = $session.CreateUpdateDownloader(); $d.Updates = $list; [void]$d.Download(); Done 'OK' Green }
        catch { Done 'ERREUR' Red; return }

        $okPass = 0
        for ($i = 0; $i -lt $list.Count; $i++) {
            $u = $list.Item($i)
            Step ("[{0}/{1}] {2}" -f ($i + 1), $list.Count, $u.Title)
            $one = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$one.Add($u)
            try {
                $inst = $session.CreateUpdateInstaller(); $inst.Updates = $one
                $res = $inst.Install(); $c = [int]$res.ResultCode
                if ($res.RebootRequired) { $s.Reboot = $true }
            } catch { $c = 4 }
            if ($c -eq 2 -or $c -eq 3) { Done 'OK' Green; $s.Wok++; $okPass++ } else { Done 'ECHEC' Red; $s.Wko++ }
        }
        if ($s.Reboot -or $okPass -eq 0) { return }
    }
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

function Invoke-Apps($s) {
    Section 'Applications (winget)'
    $wg = Get-Winget
    if (-not $wg) { Step 'winget'; Done 'ABSENT' Yellow; return }
    Step 'Recherche des mises a jour'
    $apps = @(Get-WingetUpgrades $wg)
    if ($apps.Count -eq 0) { Done 'A JOUR' Green; return }
    Done "$($apps.Count) trouvee(s)" Yellow
    $i = 0
    foreach ($a in $apps) {
        $i++
        Step ("[{0}/{1}] {2}  {3} -> {4}" -f $i, $apps.Count, $a.Name, $a.Version, $a.Available)
        if ($a.Id.EndsWith([string][char]0x2026)) { Done 'IGNORE' Yellow; $s.Ako++; continue }
        $code = Run-Quiet $wg ("upgrade --id `"{0}`" --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity" -f $a.Id)
        if ($code -eq 0) { Done 'OK' Green; $s.Aok++ } else { Done 'ECHEC' Red; $s.Ako++ }
    }
}

function Do-Update($wu, $apps) {
    $t0 = Get-Date
    $s = @{ Wok = 0; Wko = 0; Aok = 0; Ako = 0; Reboot = $false }
    if ($wu)   { Invoke-WU $s }
    if ($apps) { Invoke-Apps $s }
    Section 'Resume'
    if ($wu)   { Info 'Windows Update' ("{0} installee(s), {1} echec(s)" -f $s.Wok, $s.Wko) $(if ($s.Wko) { 'Yellow' } else { 'Green' }) }
    if ($apps) { Info 'Applications' ("{0} mise(s) a jour, {1} echec(s)" -f $s.Aok, $s.Ako) $(if ($s.Ako) { 'Yellow' } else { 'Green' }) }
    Info 'Duree' ("{0:hh\:mm\:ss}" -f ((Get-Date) - $t0))
    if ($s.Reboot) { Need-Reboot }
}

# ================= Diagnostic =================
function Get-VolumeSection {
    $rows = @()
    foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter)) {
        $pct = if ($v.Size) { [math]::Round(($v.Size - $v.SizeRemaining) / $v.Size * 100) } else { 0 }
        $c = if ($pct -ge 90) { 'Red' } elseif ($pct -ge 75) { 'Yellow' } else { 'Green' }
        $rows += (Row ("Volume {0}:" -f $v.DriveLetter) ("{0} libres sur {1} ({2} % utilises)" -f (Fmt $v.SizeRemaining), (Fmt $v.Size), $pct) $c)
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
    $ramSpeed = ($ram | Select-Object -First 1).ConfiguredClockSpeed
    if (-not $ramSpeed) { $ramSpeed = ($ram | Select-Object -First 1).Speed }

    $sys = @(
        Row 'Nom du PC' $env:COMPUTERNAME
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
    foreach ($d in @(Get-PhysicalDisk | Sort-Object DeviceId)) {
        $rel = $null
        try { $rel = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
        $h = [string]$d.HealthStatus
        $hc = switch ($h) { 'Healthy' { 'Green' } 'Warning' { 'Yellow' } default { 'Red' } }
        $ht = switch ($h) { 'Healthy' { 'Bon' } 'Warning' { 'Degrade' } 'Unhealthy' { 'Critique' } default { $h } }
        $rows = @(
            Row 'Etat' $ht $hc
            Row 'Type' ("{0} ({1})" -f $d.MediaType, $d.BusType)
            Row 'Capacite' (Fmt $d.Size)
        )
        if ($rel) {
            if ($rel.Temperature) { $rows += (Row 'Temperature' ("{0} C" -f $rel.Temperature) $(if ($rel.Temperature -ge 60) { 'Yellow' } else { 'Gray' })) }
            if ($null -ne $rel.Wear) { $rows += (Row 'Usure' ("{0} %" -f $rel.Wear) $(if ($rel.Wear -ge 80) { 'Red' } elseif ($rel.Wear -ge 50) { 'Yellow' } else { 'Green' })) }
            if ($rel.PowerOnHours) { $rows += (Row 'Heures de fonct.' ("{0:N0} h" -f $rel.PowerOnHours)) }
            if ($null -ne $rel.ReadErrorsUncorrected) { $rows += (Row 'Erreurs de lecture' $rel.ReadErrorsUncorrected $(if ($rel.ReadErrorsUncorrected -gt 0) { 'Red' } else { 'Green' })) }
        }
        @{ T = ("Disque {0} - {1}" -f $d.DeviceId, $d.FriendlyName); R = $rows }
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
    $html = "<!DOCTYPE html><html lang='fr'><head><meta charset='utf-8'><title>Rapport $env:COMPUTERNAME</title><style>$css</style></head><body><h1>Rapport RMutils - $env:COMPUTERNAME</h1><p class='sub'>Genere le $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>$($sb.ToString())</body></html>"
    $f = Join-Path (Get-ExportDir) ("rapport_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
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

function Do-Clean {
    $G.Freed = 0
    Clean-Path 'Temporaires (utilisateur)' $env:TEMP
    Clean-Path 'Temporaires (Windows)' "$env:windir\Temp"

    Step 'Cache Windows Update'
    $p = "$env:windir\SoftwareDistribution\Download"
    $b = Get-Size $p
    try { Stop-Service wuauserv, bits -Force -ErrorAction Stop } catch {}
    Get-ChildItem $p -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Service bits, wuauserv -ErrorAction SilentlyContinue
    $f = [math]::Max(0, $b - (Get-Size $p)); $G.Freed += $f
    Done (Fmt $f) $(if ($f -gt 0) { 'Green' } else { 'DarkGray' })

    Clean-Path 'Miniatures' "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" 'thumbcache_*.db'
    Clean-Path "Rapports d'erreurs" "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
    Clean-Path 'Dumps de plantage' "$env:LOCALAPPDATA\CrashDumps"

    Step 'Optimisation de distribution'
    try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null; Done 'OK' Green } catch { Done 'IGNORE' DarkGray }

    Step 'Corbeille'
    try { Clear-RecycleBin -Force -ErrorAction Stop } catch {}
    Done 'VIDEE' Green

    Section 'Resume'
    Info 'Espace libere' (Fmt $G.Freed) Green
}

function Do-Components {
    $drv = $env:SystemDrive.Substring(0, 1)
    $b = (Get-PSDrive $drv).Free
    $r = Run-Long 'DISM : nettoyage des composants' 'dism.exe' '/Online /Cleanup-Image /StartComponentCleanup' 'Oem'
    if ($r.Code -eq 0) { Done 'OK' Green } else { Done 'ECHEC' Red; Show-Tail $r.Lines 2 }
    $a = (Get-PSDrive $drv).Free
    Section 'Resume'
    Info 'Espace libere' (Fmt ([math]::Max(0, $a - $b))) Green
}

# ================= Reparation =================
function Do-RestorePoint { New-RP ("RMutils - manuel {0:dd/MM/yyyy HH:mm}" -f (Get-Date)) }

function Do-SfcDism {
    New-RP 'RMutils - avant SFC/DISM'
    $r = Run-Long "DISM : reparation de l'image Windows" 'dism.exe' '/Online /Cleanup-Image /RestoreHealth' 'Oem'
    if ($r.Code -eq 0) { Done 'OK' Green } else { Done 'ECHEC' Red; Show-Tail $r.Lines 2 }
    $r = Run-Long 'SFC : verification des fichiers systeme' 'sfc.exe' '/scannow' 'Unicode'
    if ($r.Code -eq 0) { Done 'OK' Green } else { Done 'TERMINE' Yellow }
    Show-Tail $r.Lines 2
}

function Reset-Folder($p) {
    try {
        $old = "$p.old"
        if (Test-Path $old) { Remove-Item $old -Recurse -Force -ErrorAction Stop }
        if (Test-Path $p) { Rename-Item $p (Split-Path $old -Leaf) -ErrorAction Stop }
        Done 'OK' Green
    } catch { Done 'ECHEC' Red }
}

function Do-WUReset {
    New-RP 'RMutils - avant reset Windows Update'
    Step 'Arret des services'
    try { Stop-Service wuauserv, bits, cryptsvc, msiserver -Force -ErrorAction Stop; Done 'OK' Green } catch { Done 'PARTIEL' Yellow }
    Step 'Reinitialisation de SoftwareDistribution'; Reset-Folder "$env:windir\SoftwareDistribution"
    Step 'Reinitialisation de catroot2'; Reset-Folder "$env:windir\System32\catroot2"
    Step 'Redemarrage des services'
    try { Start-Service cryptsvc, bits, wuauserv -ErrorAction Stop; Done 'OK' Green } catch { Done 'ECHEC' Red }
}

function Run-Cmd($label, $exe, $a) {
    Step $label
    if ((Run-Quiet $exe $a) -eq 0) { Done 'OK' Green } else { Done 'AVERTISSEMENT' Yellow }
}

function Do-NetReset {
    New-RP 'RMutils - avant reset reseau'
    Run-Cmd 'Vidage du cache DNS' 'ipconfig.exe' '/flushdns'
    Run-Cmd 'Reinitialisation de Winsock' 'netsh.exe' 'winsock reset'
    Run-Cmd 'Reinitialisation de la pile IPv4' 'netsh.exe' 'int ipv4 reset'
    Run-Cmd 'Reinitialisation de la pile IPv6' 'netsh.exe' 'int ipv6 reset'
    Need-Reboot
}

function Do-Chkdsk {
    $r = Run-Long "Analyse en ligne de $env:SystemDrive" 'chkdsk.exe' "$env:SystemDrive /scan" 'Oem'
    if ($r.Code -eq 0) { Done 'AUCUN PROBLEME' Green; return }
    Done 'PROBLEMES DETECTES' Yellow
    Show-Tail $r.Lines 3
    Write-Host ""
    if (Ask-YesNo 'Planifier la reparation au prochain demarrage ?') {
        Step 'Planification de la reparation'
        if ((Run-Quiet 'fsutil.exe' "dirty set $env:SystemDrive") -eq 0) { Done 'OK' Green; Need-Reboot } else { Done 'ECHEC' Red }
    }
}

# ================= Sauvegarde / restauration =================
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

function Do-ExportDrivers {
    $d = Join-Path (Get-ExportDir) 'pilotes'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $r = Run-Long 'Export des pilotes tiers' 'dism.exe' "/Online /Export-Driver /Destination:`"$d`"" 'Oem'
    $n = @(Get-ChildItem $d -Directory -ErrorAction SilentlyContinue).Count
    if ($r.Code -eq 0) { Done "$n pilote(s)" Green } else { Done 'ECHEC' Red; Show-Tail $r.Lines 2 }
    Info 'Dossier' $d
}

function Do-ExportWifi {
    $d = Join-Path (Get-ExportDir) 'wifi'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Step 'Export des profils Wi-Fi'
    $null = Run-Quiet 'netsh.exe' "wlan export profile key=clear folder=`"$d`""
    $n = @(Get-ChildItem $d -Filter *.xml -ErrorAction SilentlyContinue).Count
    if ($n -gt 0) { Done "$n profil(s)" Green } else { Done 'AUCUN' Yellow }
    Info 'Dossier' $d
    Write-Host ""
    Write-Host "  /!\ Les mots de passe Wi-Fi sont en clair dans ces fichiers." -ForegroundColor Yellow
}

function Do-RestoreDrivers {
    $src = Pick-Source 'pilotes'
    if (-not $src) { return }
    New-RP 'RMutils - avant restauration pilotes'
    $d = Join-Path $src 'pilotes'
    $r = Run-Long ("Installation des pilotes de " + (Split-Path $src -Leaf)) 'pnputil.exe' "/add-driver `"$d\*.inf`" /subdirs /install" 'Oem'
    if ($r.Code -eq 0) { Done 'OK' Green }
    elseif ($r.Code -eq 3010) { Done 'OK (redemarrage requis)' Yellow; Need-Reboot }
    else { Done 'PARTIEL' Yellow; Show-Tail $r.Lines 3 }
}

function Do-RestoreWifi {
    $src = Pick-Source 'wifi'
    if (-not $src) { return }
    foreach ($f in @(Get-ChildItem (Join-Path $src 'wifi') -Filter *.xml)) {
        $name = $f.BaseName
        try { $name = ([xml](Get-Content $f.FullName -Raw)).WLANProfile.name } catch {}
        Step "Reseau $name"
        if ((Run-Quiet 'netsh.exe' "wlan add profile filename=`"$($f.FullName)`" user=all") -eq 0) { Done 'OK' Green } else { Done 'ECHEC' Red }
    }
}

# ================= Outils : QR code =================
$QrSource = @'
using System;
using System.Collections.Generic;
using System.Text;

public static class RmQr
{
    static readonly int[] EcPerBlock = { 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26 };
    static readonly int[,] Blocks = { { 0, 0, 0, 0 }, { 1, 16, 0, 0 }, { 1, 28, 0, 0 }, { 1, 44, 0, 0 }, { 2, 32, 0, 0 }, { 2, 43, 0, 0 }, { 4, 27, 0, 0 }, { 4, 31, 0, 0 }, { 2, 38, 2, 39 }, { 3, 36, 2, 37 }, { 4, 43, 1, 44 } };
    static readonly int[][] Align = { new int[0], new int[0], new int[] { 6, 18 }, new int[] { 6, 22 }, new int[] { 6, 26 }, new int[] { 6, 30 }, new int[] { 6, 34 }, new int[] { 6, 22, 38 }, new int[] { 6, 24, 42 }, new int[] { 6, 26, 46 }, new int[] { 6, 28, 50 } };
    static readonly byte[] GfExp = new byte[512];
    static readonly byte[] GfLog = new byte[256];

    static RmQr()
    {
        int x = 1;
        for (int i = 0; i < 255; i++) { GfExp[i] = (byte)x; GfLog[x] = (byte)i; x <<= 1; if ((x & 0x100) != 0) x ^= 0x11D; }
        for (int i = 255; i < 512; i++) GfExp[i] = GfExp[i - 255];
    }

    static byte Mul(byte a, byte b) { if (a == 0 || b == 0) return 0; return GfExp[GfLog[a] + GfLog[b]]; }
    static bool Bit(int x, int i) { return ((x >> i) & 1) != 0; }

    static byte[] RsEc(byte[] data, int n)
    {
        byte[] g = new byte[] { 1 };
        for (int i = 0; i < n; i++)
        {
            byte[] ng = new byte[g.Length + 1];
            for (int j = 0; j < g.Length; j++) { ng[j] ^= g[j]; ng[j + 1] ^= Mul(g[j], GfExp[i]); }
            g = ng;
        }
        byte[] res = new byte[n];
        foreach (byte d in data)
        {
            byte f = (byte)(d ^ res[0]);
            Array.Copy(res, 1, res, 0, n - 1);
            res[n - 1] = 0;
            if (f != 0) for (int j = 0; j < n; j++) res[j] ^= Mul(g[j + 1], f);
        }
        return res;
    }

    static void Finder(bool[,] m, bool[,] f, int r, int c, int size)
    {
        for (int dr = -1; dr <= 7; dr++)
            for (int dc = -1; dc <= 7; dc++)
            {
                int y = r + dr, x = c + dc;
                if (y < 0 || x < 0 || y >= size || x >= size) continue;
                bool inside = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6;
                bool dark = inside && (dr == 0 || dr == 6 || dc == 0 || dc == 6 || (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4));
                m[y, x] = dark; f[y, x] = true;
            }
    }

    static bool MaskBit(int mask, int y, int x)
    {
        switch (mask)
        {
            case 0: return (y + x) % 2 == 0;
            case 1: return y % 2 == 0;
            case 2: return x % 3 == 0;
            case 3: return (y + x) % 3 == 0;
            case 4: return (y / 2 + x / 3) % 2 == 0;
            case 5: return (y * x) % 2 + (y * x) % 3 == 0;
            case 6: return ((y * x) % 2 + (y * x) % 3) % 2 == 0;
            default: return ((y + x) % 2 + (y * x) % 3) % 2 == 0;
        }
    }

    static void DrawFormat(bool[,] c, int size, int mask)
    {
        int data = mask; // niveau de correction M = 00
        int rem = data;
        for (int i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
        int bits = ((data << 10) | rem) ^ 0x5412;
        for (int i = 0; i <= 5; i++) c[i, 8] = Bit(bits, i);
        c[7, 8] = Bit(bits, 6); c[8, 8] = Bit(bits, 7); c[8, 7] = Bit(bits, 8);
        for (int i = 9; i < 15; i++) c[8, 14 - i] = Bit(bits, i);
        for (int i = 0; i < 8; i++) c[8, size - 1 - i] = Bit(bits, i);
        for (int i = 8; i < 15; i++) c[size - 15 + i, 8] = Bit(bits, i);
        c[size - 8, 8] = true;
    }

    static void DrawVersion(bool[,] c, int size, int ver)
    {
        int rem = ver;
        for (int i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
        int bits = (ver << 12) | rem;
        for (int i = 0; i < 18; i++) { bool b = Bit(bits, i); int a = size - 11 + i % 3, k = i / 3; c[k, a] = b; c[a, k] = b; }
    }

    static int Penalty(bool[,] m, int n)
    {
        int p = 0;
        for (int i = 0; i < n; i++)
            for (int dir = 0; dir < 2; dir++)
            {
                int run = 1;
                for (int j = 1; j < n; j++)
                {
                    bool cur = dir == 0 ? m[i, j] : m[j, i];
                    bool prev = dir == 0 ? m[i, j - 1] : m[j - 1, i];
                    if (cur == prev) run++; else { if (run >= 5) p += run - 2; run = 1; }
                }
                if (run >= 5) p += run - 2;
            }
        for (int y = 0; y < n - 1; y++)
            for (int x = 0; x < n - 1; x++)
            { bool c = m[y, x]; if (c == m[y, x + 1] && c == m[y + 1, x] && c == m[y + 1, x + 1]) p += 3; }
        bool[] p1 = { true, false, true, true, true, false, true, false, false, false, false };
        bool[] p2 = { false, false, false, false, true, false, true, true, true, false, true };
        for (int i = 0; i < n; i++)
            for (int j = 0; j <= n - 11; j++)
                for (int dir = 0; dir < 2; dir++)
                {
                    bool m1 = true, m2 = true;
                    for (int k = 0; k < 11; k++)
                    {
                        bool c = dir == 0 ? m[i, j + k] : m[j + k, i];
                        if (c != p1[k]) m1 = false;
                        if (c != p2[k]) m2 = false;
                    }
                    if (m1) p += 40;
                    if (m2) p += 40;
                }
        int dark = 0;
        foreach (bool b in m) if (b) dark++;
        int pct = dark * 100 / (n * n);
        p += Math.Abs(pct - 50) / 5 * 10;
        return p;
    }

    public static bool[,] Encode(byte[] data)
    {
        int ver = 0;
        for (int v = 1; v <= 10; v++)
        {
            int cap = (Blocks[v, 0] * Blocks[v, 1] + Blocks[v, 2] * Blocks[v, 3]) * 8;
            int need = 4 + (v < 10 ? 8 : 16) + data.Length * 8;
            if (need <= cap) { ver = v; break; }
        }
        if (ver == 0) return null;

        int dataCw = Blocks[ver, 0] * Blocks[ver, 1] + Blocks[ver, 2] * Blocks[ver, 3];
        List<bool> bits = new List<bool>();
        Action<int, int> put = (val, len) => { for (int i = len - 1; i >= 0; i--) bits.Add(((val >> i) & 1) != 0); };
        put(4, 4);
        put(data.Length, ver < 10 ? 8 : 16);
        foreach (byte b in data) put(b, 8);
        put(0, Math.Min(4, dataCw * 8 - bits.Count));
        while (bits.Count % 8 != 0) bits.Add(false);

        byte[] cw = new byte[dataCw];
        int used = bits.Count / 8;
        for (int i = 0; i < used; i++) { int v = 0; for (int j = 0; j < 8; j++) v = (v << 1) | (bits[i * 8 + j] ? 1 : 0); cw[i] = (byte)v; }
        for (int i = used, k = 0; i < dataCw; i++, k++) cw[i] = (byte)(k % 2 == 0 ? 0xEC : 0x11);

        int ec = EcPerBlock[ver];
        List<byte[]> dB = new List<byte[]>(), eB = new List<byte[]>();
        int off = 0;
        for (int g = 0; g < 2; g++)
            for (int b = 0; b < Blocks[ver, g * 2]; b++)
            {
                int len = Blocks[ver, g * 2 + 1];
                byte[] blk = new byte[len];
                Array.Copy(cw, off, blk, 0, len); off += len;
                dB.Add(blk); eB.Add(RsEc(blk, ec));
            }
        List<byte> fin = new List<byte>();
        int maxD = 0; foreach (byte[] b in dB) maxD = Math.Max(maxD, b.Length);
        for (int i = 0; i < maxD; i++) foreach (byte[] b in dB) if (i < b.Length) fin.Add(b[i]);
        for (int i = 0; i < ec; i++) foreach (byte[] b in eB) fin.Add(b[i]);

        int size = ver * 4 + 17;
        bool[,] m = new bool[size, size];
        bool[,] f = new bool[size, size];
        Finder(m, f, 0, 0, size); Finder(m, f, size - 7, 0, size); Finder(m, f, 0, size - 7, size);
        foreach (int r in Align[ver])
            foreach (int c in Align[ver])
            {
                if (f[r, c]) continue;
                for (int dr = -2; dr <= 2; dr++)
                    for (int dc = -2; dc <= 2; dc++)
                    { m[r + dr, c + dc] = Math.Max(Math.Abs(dr), Math.Abs(dc)) != 1; f[r + dr, c + dc] = true; }
            }
        for (int i = 8; i < size - 8; i++)
        {
            if (!f[6, i]) { m[6, i] = i % 2 == 0; f[6, i] = true; }
            if (!f[i, 6]) { m[i, 6] = i % 2 == 0; f[i, 6] = true; }
        }
        for (int i = 0; i < 9; i++) { f[i, 8] = true; f[8, i] = true; }
        for (int i = 0; i < 8; i++) { f[8, size - 1 - i] = true; f[size - 1 - i, 8] = true; }
        if (ver >= 7)
            for (int i = 0; i < 18; i++) { int a = size - 11 + i % 3, k = i / 3; f[k, a] = true; f[a, k] = true; }

        int bi = 0, total = fin.Count * 8;
        for (int right = size - 1; right >= 1; right -= 2)
        {
            if (right == 6) right = 5;
            for (int vert = 0; vert < size; vert++)
                for (int j = 0; j < 2; j++)
                {
                    int x = right - j;
                    bool up = ((right + 1) & 2) == 0;
                    int y = up ? size - 1 - vert : vert;
                    if (!f[y, x] && bi < total) { m[y, x] = ((fin[bi >> 3] >> (7 - (bi & 7))) & 1) != 0; bi++; }
                }
        }

        bool[,] best = null; int bestP = int.MaxValue;
        for (int mask = 0; mask < 8; mask++)
        {
            bool[,] c = (bool[,])m.Clone();
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                    if (!f[y, x] && MaskBit(mask, y, x)) c[y, x] = !c[y, x];
            DrawFormat(c, size, mask);
            if (ver >= 7) DrawVersion(c, size, ver);
            int p = Penalty(c, size);
            if (p < bestP) { bestP = p; best = c; }
        }
        return best;
    }

    static bool Dark(bool[,] m, int n, int y, int x) { return y >= 0 && x >= 0 && y < n && x < n && m[y, x]; }

    public static string[] Render(bool[,] m, int q)
    {
        int n = m.GetLength(0), t = n + 2 * q;
        List<string> lines = new List<string>();
        for (int y = 0; y < t; y += 2)
        {
            StringBuilder sb = new StringBuilder();
            for (int x = 0; x < t; x++)
            {
                bool a = Dark(m, n, y - q, x - q), b = Dark(m, n, y + 1 - q, x - q);
                sb.Append(a && b ? '\u2588' : a ? '\u2580' : b ? '\u2584' : ' ');
            }
            lines.Add(sb.ToString());
        }
        return lines.ToArray();
    }
}
'@

function Ensure-Qr { if (-not ('RmQr' -as [type])) { Add-Type -TypeDefinition $QrSource -Language CSharp } }

function Write-Qr($text) {
    Ensure-Qr
    $m = [RmQr]::Encode([Text.Encoding]::UTF8.GetBytes($text))
    if ($null -eq $m) { Note 'Texte trop long pour un QR code.'; return $false }
    Write-Host ""
    foreach ($l in [RmQr]::Render($m, 2)) { Write-Host "  " -NoNewline; Write-Host $l -ForegroundColor Black -BackgroundColor White }
    Write-Host ""
    return $true
}

function Note($t) { Write-Host ("  " + $t) -ForegroundColor DarkYellow; Log $t }

# ================= Outils : mot de passe Wi-Fi =================
function Get-WifiProfiles {
    $tmp = Join-Path $env:TEMP ("rmu_wifi_" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $null = Run-Quiet 'netsh.exe' "wlan export profile key=clear folder=`"$tmp`""
        $list = @()
        foreach ($f in @(Get-ChildItem $tmp -Filter *.xml -ErrorAction SilentlyContinue)) {
            try {
                $x = [xml](Get-Content $f.FullName -Raw)
                $p = $x.WLANProfile
                $ssid = [string]$p.SSIDConfig.SSID.name
                if (-not $ssid) { $ssid = [string]$p.name }
                $list += [pscustomobject]@{
                    Ssid   = $ssid
                    Auth   = [string]$p.MSM.security.authEncryption.authentication
                    Key    = [string]$p.MSM.security.sharedKey.keyMaterial
                    Hidden = ([string]$p.SSIDConfig.nonBroadcast -eq 'true')
                }
            } catch {}
        }
        return $list
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-CurrentSsid {
    $ErrorActionPreference = 'Continue'
    foreach ($l in @(netsh.exe wlan show interfaces)) { if ($l -match '^\s*SSID\s*:\s*(.+?)\s*$') { return $Matches[1] } }
    return $null
}

function Auth-Label($a) {
    switch ($a) {
        'open'    { 'Ouvert (sans mot de passe)' }
        'shared'  { 'WEP' }
        'WPAPSK'  { 'WPA-Personnel' }
        'WPA2PSK' { 'WPA2-Personnel' }
        'WPA3SAE' { 'WPA3-Personnel' }
        'WPA'     { 'WPA-Entreprise' }
        'WPA2'    { 'WPA2-Entreprise' }
        default   { [string]$a }
    }
}

function Esc-Wifi($s) { return ([string]$s -replace '([\\;,:"])', '\$1') }

function Do-WifiPassword {
    Step 'Lecture des reseaux enregistres'
    $profiles = @(Get-WifiProfiles)
    if ($profiles.Count -eq 0) { Done 'AUCUN' Yellow; return }
    Done "$($profiles.Count) reseau(x)" Green

    $cur = Get-CurrentSsid
    $profiles = @($profiles | Sort-Object @{ Expression = { $_.Ssid -ne $cur } }, Ssid)
    $items = @($profiles | ForEach-Object {
        $lab = $_.Ssid
        if ($cur -and $_.Ssid -eq $cur) { $lab += '  (connecte)' }
        @{ Label = $lab; Desc = @(("Securite : " + (Auth-Label $_.Auth)), "Entree : afficher le mot de passe et le QR code.") }
    })
    $items += @{ Label = 'Annuler'; Desc = @('Revenir au menu.'); Back = $true }
    $s = 0
    $r = Show-Menu ($G.Crumb + ' > Choisir le reseau') $items ([ref]$s)
    if ($r -lt 0 -or $items[$r].Back) { $G.Cancel = $true; return }
    $p = $profiles[$r]
    Show-Header $G.Crumb

    Section 'Reseau Wi-Fi'
    Info 'Nom (SSID)' $p.Ssid White
    Info 'Securite' (Auth-Label $p.Auth)
    $open = ($p.Auth -eq 'open')
    if (-not $open -and -not $p.Key) {
        Info 'Mot de passe' 'non disponible' Yellow
        Write-Host ""
        Note "Reseau d'entreprise (identifiant personnel) ou mot de passe non stocke : pas de QR code possible."
        return
    }
    # Le mot de passe est affiche mais jamais ecrit dans le log
    Write-Host ("  {0,-20}: " -f 'Mot de passe') -NoNewline -ForegroundColor DarkGray
    if ($open) { Write-Host '(aucun)' -ForegroundColor DarkGray } else { Write-Host $p.Key -ForegroundColor Green }

    $t = if ($open) { 'nopass' } elseif ($p.Auth -eq 'shared') { 'WEP' } else { 'WPA' }
    $payload = "WIFI:T:$t;S:" + (Esc-Wifi $p.Ssid) + ";"
    if (-not $open) { $payload += "P:" + (Esc-Wifi $p.Key) + ";" }
    if ($p.Hidden) { $payload += "H:true;" }
    $payload += ";"

    Section 'QR code'
    if (Write-Qr $payload) { Note "Scanne avec l'appareil photo du telephone pour se connecter directement." }
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
    @{ Label = 'Mettre a jour Windows'; Run = { Do-Update $true $false }; Desc = @(
        "Recherche, telecharge et installe toutes les MAJ proposees par Windows Update :",
        "securite, cumulatives, pilotes, Defender, .NET...",
        "Installation une par une avec statut, jusqu'a 3 passes si d'autres MAJ apparaissent.",
        "Duree : 5 a 45 min selon le retard. Redemarrage souvent necessaire.") }
    @{ Label = 'Mettre a jour les applications'; Run = { Do-Update $false $true }; Desc = @(
        "Met a jour en silencieux toutes les applis connues de winget",
        "(navigateurs, 7-Zip, Discord, VLC...).",
        "Les applis ouvertes peuvent echouer : ferme-les avant.",
        "Duree : 1 a 10 min.") }
    @{ Label = 'Tout mettre a jour'; Run = { Do-Update $true $true }; Desc = @(
        "Windows Update puis applications winget, avec un resume global a la fin.",
        "C'est l'option a lancer en premier sur un PC qui n'a pas ete entretenu.") }
    @{ Label = { "Redemarrage auto : " + $(if ($G.AutoReboot) { 'ON' } else { 'OFF' }) }; Toggle = $true; Run = { $G.AutoReboot = -not $G.AutoReboot }; Desc = @(
        "Entree pour basculer ON / OFF.",
        "ON  : redemarre tout seul 60 s apres une action qui le demande (annulable : shutdown /a).",
        "OFF : RMutils te demande O/N a la fin de l'action.") }
    $back
)

$menuDiag = @(
    @{ Label = 'Infos systeme'; Run = { Do-SysInfo }; Desc = @(
        "Resume du PC : modele, n de serie, version et activation de Windows, uptime,",
        "processeur, memoire, carte graphique, carte mere, BIOS et espace disque.",
        "Lecture seule, rien n'est modifie.") }
    @{ Label = 'Sante des disques'; Run = { Do-Disks }; Desc = @(
        "Lit l'etat SMART de chaque disque : sante, temperature, usure (SSD),",
        "heures de fonctionnement, erreurs de lecture, puis le remplissage des volumes.",
        "Etat 'Degrade' ou erreurs de lecture = sauvegarder les donnees rapidement.",
        "Certaines infos peuvent manquer selon le disque ou le controleur (USB, RAID).") }
    @{ Label = 'Etat de la batterie'; Run = { Do-Battery }; Desc = @(
        "Portables uniquement. Compare la capacite d'origine a la capacite actuelle",
        "pour calculer l'usure reelle. Sous 60 % de sante, la batterie est a changer.",
        "Genere aussi le rapport detaille Windows (powercfg) dans RMutils_export sur la cle.") }
    @{ Label = 'Diagnostic reseau'; Run = { Do-Network }; Desc = @(
        "Affiche IP, passerelle, DNS et MAC, puis teste dans l'ordre :",
        "box, Internet, resolution DNS, acces web.",
        "Le premier test en echec indique ou ca coince :",
        "box KO = cable / Wi-Fi, Internet KO = box / FAI, DNS KO = serveur DNS.") }
    @{ Label = 'Rapport HTML complet'; Run = { Do-Report }; Desc = @(
        "Genere un rapport HTML avec toutes les infos : systeme, disques, batterie,",
        "reseau et 10 dernieres MAJ, dans RMutils_export\<nom du PC>\ sur la cle.",
        "Pratique pour garder une trace de chaque PC depanne.") }
    $back
)

$menuClean = @(
    @{ Label = 'Nettoyage rapide'; Run = { Do-Clean }; Desc = @(
        "Supprime : fichiers temporaires (utilisateur + Windows), cache Windows Update,",
        "cache d'optimisation de distribution, miniatures, rapports d'erreurs, dumps.",
        "Vide aussi la corbeille. Les fichiers en cours d'utilisation sont ignores.",
        "Affiche l'espace libere. Duree : moins d'une minute en general.") }
    @{ Label = 'Nettoyage des composants Windows'; Run = { Do-Components }; Desc = @(
        "Lance DISM /StartComponentCleanup : supprime les anciennes versions des",
        "composants remplaces par les MAJ (dossier WinSxS). Peut liberer plusieurs Go.",
        "Les MAJ deja installees ne pourront plus etre desinstallees.",
        "Duree : 5 a 30 min.") }
    $back
)

$menuRepair = @(
    @{ Label = 'Creer un point de restauration'; Run = { Do-RestorePoint }; Desc = @(
        "Cree un point de restauration systeme (active la protection sur C: si besoin).",
        "Les autres reparations en creent un automatiquement avant de modifier quoi que ce soit.") }
    @{ Label = 'Reparer Windows (DISM + SFC)'; Run = { Do-SfcDism }; Desc = @(
        "1. DISM /RestoreHealth : repare l'image de Windows (via Windows Update).",
        "2. SFC /scannow : verifie et remplace les fichiers systeme corrompus.",
        "A lancer quand Windows plante, rame ou que des fonctions ne marchent plus.",
        "Duree : 15 a 45 min. Connexion Internet recommandee.") }
    @{ Label = 'Reinitialiser Windows Update'; Run = { Do-WUReset }; Desc = @(
        "Arrete les services de MAJ, renomme les caches SoftwareDistribution et catroot2",
        "(recrees vides au prochain lancement), puis relance les services.",
        "Regle la plupart des MAJ bloquees, en boucle ou en erreur.",
        "L'historique affiche dans Parametres sera vide (les MAJ restent installees).") }
    @{ Label = 'Reinitialiser le reseau'; Run = { Do-NetReset }; Desc = @(
        "Vide le cache DNS, reinitialise Winsock et les piles IPv4 / IPv6.",
        "A utiliser quand Internet ne marche plus sans raison apparente.",
        "Redemarrage necessaire. Les IP fixes eventuelles devront etre reconfigurees.") }
    @{ Label = 'Verifier le disque systeme'; Run = { Do-Chkdsk }; Desc = @(
        "Lance chkdsk /scan sur le disque systeme (en ligne, sans redemarrer).",
        "Si des erreurs sont trouvees, propose de planifier la reparation au demarrage.",
        "Duree : 2 a 15 min.") }
    $back
)

$menuBackup = @(
    @{ Label = 'Exporter les pilotes'; Run = { Do-ExportDrivers }; Desc = @(
        "Copie tous les pilotes tiers installes (reseau, Wi-Fi, audio, chipset...)",
        "dans RMutils_export\<nom du PC>\pilotes sur la cle.",
        "A faire AVANT une reinstallation, pour ne pas se retrouver sans Wi-Fi apres.") }
    @{ Label = 'Exporter les profils Wi-Fi'; Run = { Do-ExportWifi }; Desc = @(
        "Sauvegarde tous les reseaux Wi-Fi connus avec leur mot de passe",
        "dans RMutils_export\<nom du PC>\wifi sur la cle.",
        "Attention : les mots de passe sont stockes en clair.") }
    @{ Label = 'Restaurer des pilotes'; Run = { Do-RestoreDrivers }; Desc = @(
        "Choisis une sauvegarde presente sur la cle, puis installe tous ses pilotes (pnputil).",
        "Utile juste apres une reinstallation de Windows.",
        "Les pilotes sans materiel correspondant sont ignores. Redemarrage parfois requis.") }
    @{ Label = 'Restaurer des profils Wi-Fi'; Run = { Do-RestoreWifi }; Desc = @(
        "Choisis une sauvegarde presente sur la cle et reimporte tous ses reseaux Wi-Fi.",
        "Le PC se reconnectera tout seul aux reseaux connus.") }
    $back
)

$menuInstall = @(
    @{ Label = "Installer le pack d'applications"; Run = { Do-AppPack }; Desc = @(
        "Installe en silencieux les applis listees dans RMutils_apps.txt (racine de la cle).",
        "Liste par defaut creee au 1er lancement : Firefox, 7-Zip, VLC, Notepad++, Acrobat Reader.",
        "Les applis deja presentes sont ignorees.") }
    @{ Label = 'Modifier la liste des applications'; Run = { Do-EditApps }; NoPause = $true; Desc = @(
        "Ouvre RMutils_apps.txt dans le Bloc-notes.",
        "Un identifiant winget par ligne. Pour en trouver un : winget search <nom>",
        "Exemples : Google.Chrome, Discord.Discord, Valve.Steam, TheDocumentFoundation.LibreOffice") }
    $back
)

$menuTools = @(
    @{ Label = 'Mot de passe Wi-Fi'; Run = { Do-WifiPassword }; Desc = @(
        "Affiche le mot de passe d'un reseau Wi-Fi enregistre sur ce PC",
        "(le reseau connecte est propose en premier), avec son QR code dans le terminal.",
        "Scanne-le avec l'appareil photo d'un telephone pour se connecter sans rien taper.",
        "Le mot de passe n'est jamais ecrit dans le log.") }
    $back
)

$main = @(
    @{ Label = 'Mises a jour'; Items = $menuMaj; Sel = 0; Desc = @(
        "Windows Update, mises a jour des applications (winget), ou les deux.",
        "Reglage du redemarrage automatique.") }
    @{ Label = 'Diagnostic'; Items = $menuDiag; Sel = 0; Desc = @(
        "Infos systeme, sante des disques, etat de la batterie, diagnostic reseau",
        "et rapport HTML complet a garder sur la cle.",
        "Lecture seule : rien n'est modifie sur le PC.") }
    @{ Label = 'Nettoyage'; Items = $menuClean; Sel = 0; Desc = @(
        "Fichiers temporaires, caches, corbeille,",
        "et anciennes versions des composants Windows.") }
    @{ Label = 'Reparation'; Items = $menuRepair; Sel = 0; Desc = @(
        "Point de restauration, DISM + SFC, reinitialisation de Windows Update",
        "et du reseau, verification du disque.",
        "Un point de restauration est cree avant chaque reparation.") }
    @{ Label = 'Sauvegarde et restauration'; Items = $menuBackup; Sel = 0; Desc = @(
        "Export et restauration des pilotes et des profils Wi-Fi via la cle.",
        "A utiliser avant et apres une reinstallation de Windows.") }
    @{ Label = 'Installation'; Items = $menuInstall; Sel = 0; Desc = @(
        "Installation silencieuse d'un pack d'applications",
        "pour un PC neuf ou fraichement reinstalle.") }
    @{ Label = 'Outils'; Items = $menuTools; Sel = 0; Desc = @(
        "Outils du quotidien.",
        "Mot de passe Wi-Fi avec QR code a scanner directement dans le terminal.") }
    @{ Label = 'Quitter'; Quit = $true; Desc = @(
        "Ferme RMutils.",
        "Le log de la session reste dans RMutils_logs sur la cle.") }
)

function Finish {
    if ($G.RebootAsk) { $G.RebootAsk = $false; Ask-Reboot }
    Write-Host ""
    Write-Host "  Appuie sur une touche pour revenir au menu..." -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

# ================= Boucle principale =================
Log "=== RMutils demarre sur $pcInfo ==="
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
        if ($it.Toggle) { & $it.Run; continue }

        $G.Crumb = "Menu principal > {0} > {1}" -f $cat.Label, (Label-Of $it)
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
