# install-from-usb.ps1
# Installs drivers from a Drivers folder and applications from a Software folder located on the installation USB (commonly D:\) or in C:\Software.
# Intended to run elevated (SYSTEM) from SetupComplete.cmd after Windows Setup.

$LogFile = "C:\Windows\Temp\usb-install.log"
Function Log { param($m) $t = Get-Date -Format s; "$t - $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }
Log "===== install-from-usb.ps1 started ====="

# Helper: find a drive that contains a given folder name at root
Function Find-DriveWithFolder([string]$folderName) {
    # Check common letter D: first
    $tryLetters = @('D','E','F','G','H')
    foreach ($l in $tryLetters) {
        $p = "$l:\$folderName"
        if (Test-Path $p) { return "$l:`\" }
    }

    # Check all filesystem PS drives (exclude C which will be target)
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        if ($_.Name -ne 'C') {
            $root = "$($_.Name):\"
            if (Test-Path (Join-Path $root $folderName)) { return $root }
        }
    }

    return $null
}

# Detect source paths
$usbSoftwareDrive = Find-DriveWithFolder -folderName 'Software'
$usbDriversDrive = Find-DriveWithFolder -folderName 'Drivers'

if ($usbSoftwareDrive) { Log "Found Software on drive: $usbSoftwareDrive" } else { Log "No Software folder found on removable drives. Will check C:\Software as fallback." }
if ($usbDriversDrive) { Log "Found Drivers on drive: $usbDriversDrive" } else { Log "No Drivers folder found on removable drives. Will check C:\Drivers as fallback." }

$softwarePath = $null
$driversPath = $null

if ($usbSoftwareDrive -and (Test-Path (Join-Path $usbSoftwareDrive 'Software'))) {
    $softwarePath = Join-Path $usbSoftwareDrive 'Software'
} elseif (Test-Path 'C:\Software') {
    $softwarePath = 'C:\Software'
}

if ($usbDriversDrive -and (Test-Path (Join-Path $usbDriversDrive 'Drivers'))) {
    $driversPath = Join-Path $usbDriversDrive 'Drivers'
} elseif (Test-Path 'C:\Drivers') {
    $driversPath = 'C:\Drivers'
}

Log "Effective Software path: $softwarePath"
Log "Effective Drivers path: $driversPath"

# Install drivers using pnputil from the drivers path (INF files)
if ($driversPath -and (Test-Path $driversPath)) {
    Log "Installing drivers from $driversPath"
    $infFiles = Get-ChildItem -Path $driversPath -Recurse -Include *.inf -ErrorAction SilentlyContinue
    if ($infFiles.Count -eq 0) { Log "No .inf files found under $driversPath" }
    foreach ($inf in $infFiles) {
        try {
            Log "Attempting pnputil /add-driver `"$($inf.FullName)`" /install"
            $p = Start-Process -FilePath pnputil.exe -ArgumentList "/add-driver `"$($inf.FullName)`" /install" -Wait -NoNewWindow -PassThru -ErrorAction Stop
            Log "pnputil exit code: $($p.ExitCode)"
        } catch {
            Log "Driver install failed for $($inf.FullName): $_"
        }
    }
} else { Log "Drivers path not found or empty: $driversPath" }

# Install software from software path
if ($softwarePath -and (Test-Path $softwarePath)) {
    Log "Installing software from $softwarePath"

    # Install MSIs
    $msis = Get-ChildItem -Path $softwarePath -Recurse -Include *.msi -ErrorAction SilentlyContinue
    foreach ($msi in $msis) {
        try {
            Log "Installing MSI: $($msi.FullName)"
            $p = Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$($msi.FullName)`" /qn /norestart" -Wait -NoNewWindow -PassThru -ErrorAction Stop
            Log "msiexec exit code: $($p.ExitCode)"
        } catch {
            Log "MSI install failed for $($msi.FullName): $_"
        }
    }

    # Install EXEs with known per-installer silent switches and fallback list
    $exeSilentArgsMap = @{
        'chrome' = @('/silent','/install','/S')
        'googlechrome' = @('/silent','/install','/S')
        '7z' = @('/S')
        '7-zip' = @('/S')
        'vlc' = @('/S')
    }
    $exeSwitches = @('/S','/silent','/VERYSILENT','/quiet','/qn','/s','/SILENT','/verysilent','/silentinstall','/install','/passive')
    $exes = Get-ChildItem -Path $softwarePath -Recurse -Include *.exe -ErrorAction SilentlyContinue
    foreach ($exe in $exes) {
        Log "Processing EXE: $($exe.FullName)"
        $installed = $false
        $base = $exe.Name.ToLower()
        # try mapped switches first based on filename
        foreach ($pattern in $exeSilentArgsMap.Keys) {
            if ($base -like "*$pattern*") {
                foreach ($sw in $exeSilentArgsMap[$pattern]) {
                    try {
                        Log "Trying mapped switch $sw for $($exe.Name) (pattern: $pattern)"
                        $p = Start-Process -FilePath $exe.FullName -ArgumentList $sw -Wait -NoNewWindow -PassThru -ErrorAction Stop
                        Log "Return code for $($exe.Name) with $sw: $($p.ExitCode)"
                        if ($p.ExitCode -eq 0) { $installed = $true; break }
                    } catch { Log "Mapped attempt with $sw failed: $_" }
                }
                if ($installed) { break }
            }
        }
        # fallback to common switches
        if (-not $installed) {
            foreach ($sw in $exeSwitches) {
                try {
                    Log "Trying fallback switch $sw for $($exe.Name)"
                    $p = Start-Process -FilePath $exe.FullName -ArgumentList $sw -Wait -NoNewWindow -PassThru -ErrorAction Stop
                    Log "Return code for $($exe.Name) with $sw: $($p.ExitCode)"
                    if ($p.ExitCode -eq 0) { $installed = $true; break }
                } catch { Log "Fallback attempt with $sw failed: $_" }
            }
        }
        if (-not $installed) { Log "Could not silently install $($exe.Name). Manual intervention may be required." } else { Log "$($exe.Name) installed." }
    }
} else { Log "Software path not found or empty: $softwarePath" }

Log "===== install-from-usb.ps1 completed ====="
exit 0
