# install-chrome-7zip-vlc.ps1
# Downloads and installs Google Chrome, 7-Zip and VLC.
# Designed to run elevated (SYSTEM) from SetupComplete.cmd or manually.

$LogFile = "C:\Windows\Temp\install-apps.log"
Function Log { param($m) $t = Get-Date -Format s; "$t - $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$installDir = 'C:\Software\Installers'
if (-not (Test-Path $installDir)) { New-Item -Path $installDir -ItemType Directory -Force | Out-Null }

Function Is-Installed([string]$pattern) {
    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($h in $hives) {
        try {
            Get-ItemProperty -Path "$h\*" -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -and ($_.DisplayName -match $pattern) } | ForEach-Object { return $true }
        } catch { }
    }
    return $false
}

Function Try-WingetInstall([string]$id,[string]$friendly) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Log "Attempting winget install for $friendly ($id)"
        try {
            & winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements 2>> $LogFile
            if ($LASTEXITCODE -eq 0) { Log "$friendly installed via winget."; return $true }
            Log "winget returned exitcode $LASTEXITCODE for $friendly"
        } catch { Log "winget install error: $_" }
    } else { Log "winget not found" }
    return $false
}

Function Download-File($url, $out) {
    Log "Downloading $url to $out"
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
        Log "Downloaded $out"
        return $true
    } catch { Log "Download failed: $_"; return $false }
}

# Package definitions (fallback URLs used only if winget not available)
$packages = @(
    @{ Name = 'Google Chrome'; Id='Google.Chrome'; Check='Chrome'; Url='https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi'; Type='msi' },
    @{ Name = '7-Zip'; Id='7zip.7zip'; Check='7-Zip'; Url='https://www.7-zip.org/a/7z1900-x64.exe'; Type='exe'; SilentArgs='/S' },
    @{ Name = 'VLC media player'; Id='VideoLAN.VLC'; Check='VLC'; Url='https://get.videolan.org/vlc/3.0.18/win64/vlc-3.0.18-win64.exe'; Type='exe'; SilentArgs='/S' }
)

foreach ($pkg in $packages) {
    $name = $pkg.Name
    Log "--- Processing $name ---"
    if (Is-Installed $pkg.Check) { Log "$name already installed; skipping"; continue }

    $installed = $false
    # Try winget first
    if (Try-WingetInstall $pkg.Id $name) { $installed = $true }

    if (-not $installed) {
        $fileName = Join-Path $installDir ([IO.Path]::GetFileName($pkg.Url))
        if (-not (Test-Path $fileName)) {
            if (-not (Download-File $pkg.Url $fileName)) { Log "Failed to fetch $name from $($pkg.Url). Skipping."; continue }
        } else { Log "Installer already present: $fileName" }

        try {
            if ($pkg.Type -eq 'msi') {
                Log "Installing MSI: $fileName"
                $p = Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$fileName`" /qn /norestart" -Wait -NoNewWindow -PassThru
                Log "msiexec exitcode: $($p.ExitCode)"
                if ($p.ExitCode -eq 0) { $installed = $true }
            } elseif ($pkg.Type -eq 'exe') {
                $sw = $pkg.SilentArgs ? $pkg.SilentArgs : '/S'
                Log "Installing EXE: $fileName with args: $sw"
                $p = Start-Process -FilePath $fileName -ArgumentList $sw -Wait -NoNewWindow -PassThru
                Log "exe exitcode: $($p.ExitCode)"
                if ($p.ExitCode -eq 0) { $installed = $true }
            }
        } catch {
            Log "Installation error for $name: $_"
        }
    }

    if ($installed) { Log "$name installed successfully." } else { Log "$name failed to install. Check $LogFile for details." }
}

Log "All done."

# Optionally: remove installers (uncomment to enable)
# Remove-Item -Path (Join-Path $installDir '*') -Force -Recurse -ErrorAction SilentlyContinue

exit 0
