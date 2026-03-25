#Requires -Version 5.1
# ==============================================================
#  DEXTER TOOLKIT -- Build & Setup  [Windows]
#  Clones tools, creates venv, downloads binaries
# ==============================================================

param(
    [switch]$SkipGoTools,
    [switch]$SkipBinaries
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$SCRIPT_DIR = Split-Path -Parent (Resolve-Path $PSCommandPath)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$E   = [char]27
$G   = "${E}[1;32m"; $Y = "${E}[1;33m"; $C = "${E}[1;36m"
$R   = "${E}[1;31m"; $D = "${E}[2m";    $RST = "${E}[0m"

function Write-Step([string]$msg) { Write-Host ($C + "[*] " + $RST + $msg) }
function Write-OK([string]$msg)   { Write-Host ($G + "[+] " + $RST + $msg) }
function Write-Warn([string]$msg) { Write-Host ($Y + "[!] " + $RST + $msg) }
function Write-Fail([string]$msg) { Write-Host ($R + "[x] " + $RST + $msg) }

Write-Host ($C + "  DEXTER TOOLKIT  --  Build & Setup (Windows)" + $RST)
Write-Host ($D + "  Tonight is the night." + $RST + "`n")

# -- Helpers ---------------------------------------------------
function Test-Cmd([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-GitClone([string]$Url, [string]$Dest, [string]$Name) {
    if (Test-Path $Dest) {
        Write-OK "$Name already present -- skipping"
        return
    }
    Write-Step "Cloning $Name..."
    & git clone --depth 1 $Url $Dest 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-OK "$Name cloned" }
    else { Write-Warn "Failed to clone $Name" }
}

function Get-GithubLatestAsset([string]$Repo, [string]$Pattern) {
    try {
        $headers = @{ Accept = 'application/vnd.github.v3+json'; 'User-Agent' = 'dexter-build' }
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -ErrorAction Stop
        return $rel.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    } catch {
        return $null
    }
}

function Download-File([string]$Url, [string]$Dest) {
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
}

# -- Prerequisites ---------------------------------------------
Write-Step "Checking prerequisites..."

$hasPython = Test-Cmd 'python'
$hasGit    = Test-Cmd 'git'
$hasGo     = Test-Cmd 'go'

if (-not $hasGit) {
    Write-Fail "git not found. Install from https://git-scm.com and re-run."
    exit 1
}
if (-not $hasPython) { Write-Warn "python not found -- Python tools will be skipped" }
else                  { Write-OK  "python found" }
if (-not $hasGo)      { Write-Warn "go not found -- Go tools will be skipped (optional)" }
else                  { Write-OK  "go found" }

# -- Directories -----------------------------------------------
$ToolsDir = Join-Path $SCRIPT_DIR "tools"
$BinDir   = Join-Path $SCRIPT_DIR "bin"
New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
New-Item -ItemType Directory -Path $BinDir   -Force | Out-Null

# -- Clone tool repositories -----------------------------------
Write-Host ""
Write-Step "Setting up tool repositories..."

Invoke-GitClone "https://github.com/sqlmapproject/sqlmap.git" (Join-Path $ToolsDir "sqlmap")    "sqlmap"
Invoke-GitClone "https://github.com/s0md3v/XSStrike.git"      (Join-Path $ToolsDir "XSStrike")  "XSStrike"
Invoke-GitClone "https://github.com/maurosoria/dirsearch.git" (Join-Path $ToolsDir "dirsearch") "dirsearch"
Invoke-GitClone "https://github.com/fortra/impacket.git"      (Join-Path $ToolsDir "impacket")  "impacket"

# -- Download binaries -----------------------------------------
if (-not $SkipBinaries) {
    Write-Host ""
    Write-Step "Downloading Windows binaries..."

    # nmap -- installed via winget (handles UAC automatically)
    if (Test-Cmd 'nmap') {
        Write-OK "nmap found in PATH"
    } else {
        $nmapDefault = "C:\Program Files (x86)\Nmap\nmap.exe"
        if (Test-Path $nmapDefault) {
            Write-OK "nmap found -- adding to PATH"
            $env:PATH = "C:\Program Files (x86)\Nmap;$env:PATH"
        } elseif (Test-Cmd 'winget') {
            Write-Step "Installing nmap via winget (UAC prompt may appear)..."
            winget install --id nmap.nmap --silent --accept-package-agreements --accept-source-agreements
            if (Test-Path $nmapDefault) {
                $env:PATH = "C:\Program Files (x86)\Nmap;$env:PATH"
                Write-OK "nmap installed"
            } else {
                Write-Warn "nmap installed -- restart terminal to use it"
            }
        } else {
            Write-Warn "winget not found -- install nmap manually: https://nmap.org/download.html"
        }
    }

    # rustscan
    $rustscanDest = Join-Path $BinDir "rustscan.exe"
    if (Test-Path $rustscanDest) {
        Write-OK "rustscan.exe already present"
    } else {
        Write-Step "Fetching latest rustscan release..."
        $asset = Get-GithubLatestAsset "RustScan/RustScan" "windows.*x86_64.*\.exe"
        if (-not $asset) { $asset = Get-GithubLatestAsset "RustScan/RustScan" "\.exe" }
        if ($asset) {
            try {
                Write-Step "Downloading $($asset.name)..."
                Download-File $asset.browser_download_url $rustscanDest
                Write-OK "rustscan.exe saved to bin\"
            } catch {
                Write-Warn "Failed to download rustscan: $_"
            }
        } else {
            Write-Warn "No Windows rustscan binary found -- get it from github.com/RustScan/RustScan/releases"
        }
    }

    # chisel
    $chiselDest = Join-Path $BinDir "chisel.exe"
    if (Test-Path $chiselDest) {
        Write-OK "chisel.exe already present"
    } else {
        Write-Step "Fetching latest chisel release..."
        $asset = Get-GithubLatestAsset "jpillora/chisel" "windows_amd64"
        if ($asset) {
            try {
                $assetName = $asset.name
                $ext = if ($assetName -like "*.zip") { ".zip" } else { ".gz" }
                $tmp = [IO.Path]::GetTempFileName() + $ext
                Write-Step "Downloading $assetName..."
                Download-File $asset.browser_download_url $tmp

                if ($assetName -like "*.gz") {
                    $bytes = [IO.File]::ReadAllBytes($tmp)
                    $ms  = New-Object IO.MemoryStream (,$bytes)
                    $gz  = New-Object IO.Compression.GZipStream ($ms, [IO.Compression.CompressionMode]::Decompress)
                    $out = New-Object IO.MemoryStream
                    $gz.CopyTo($out)
                    [IO.File]::WriteAllBytes($chiselDest, $out.ToArray())
                    $gz.Dispose(); $ms.Dispose()
                } elseif ($assetName -like "*.zip") {
                    $tmpDir = Join-Path $env:TEMP "chisel_extract"
                    Expand-Archive -Path $tmp -DestinationPath $tmpDir -Force
                    $exe = Get-ChildItem $tmpDir -Filter "chisel*.exe" -Recurse | Select-Object -First 1
                    if ($exe) { Move-Item $exe.FullName $chiselDest -Force }
                    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                if (Test-Path $chiselDest) { Write-OK "chisel.exe saved to bin\" }
            } catch {
                Write-Warn "Failed to extract chisel: $_"
            }
        } else {
            Write-Warn "chisel not found -- install manually if needed"
        }
    }
}

# -- Python virtual environment --------------------------------
if ($hasPython) {
    Write-Host ""
    Write-Step "Setting up Python virtual environment..."

    $VenvDir   = Join-Path $SCRIPT_DIR ".venv"
    if (-not (Test-Path $VenvDir)) {
        & python -m venv $VenvDir 2>&1 | Out-Null
        if (Test-Path $VenvDir) { Write-OK "venv created at .venv\" }
        else { Write-Warn "venv creation failed -- skipping Python setup"; return }
    } else {
        Write-OK "venv already exists"
    }

    $PythonExe = Join-Path $VenvDir "Scripts\python.exe"
    $PipCmd    = Join-Path $VenvDir "Scripts\pip.exe"

    # Ensure pip is available inside the venv (some Windows installs omit it)
    if (-not (Test-Path $PythonExe)) {
        Write-Warn "venv python.exe not found -- trying python3"
        $PythonExe = Join-Path $VenvDir "Scripts\python3.exe"
    }
    if (-not (Test-Path $PipCmd)) {
        Write-Step "pip not found in venv -- bootstrapping with ensurepip..."
        & $PythonExe -m ensurepip --upgrade 2>&1 | Out-Null
        & $PythonExe -m pip install --upgrade pip --quiet 2>&1 | Out-Null
        if (-not (Test-Path $PipCmd)) {
            Write-Warn "Could not bootstrap pip -- Python packages will be skipped"
            $hasPython = $false
        }
    }

    if ($hasPython) {
        Write-Step "Upgrading pip..."
        & $PythonExe -m pip install --upgrade pip --quiet 2>&1 | Out-Null
    }

    if (-not $hasPython) { return }

    Write-Step "Installing Python packages (wafw00f, semgrep, git-dumper, bloodhound)..."
    & $PipCmd install wafw00f semgrep git-dumper bloodhound --quiet 2>&1 | Out-Null
    Write-OK "Core Python packages installed"

    foreach ($reqPath in @(
        (Join-Path $ToolsDir "XSStrike\requirements.txt"),
        (Join-Path $ToolsDir "dirsearch\requirements.txt")
    )) {
        if (Test-Path $reqPath) {
            $toolName = Split-Path (Split-Path $reqPath) -Leaf
            Write-Step "Installing $toolName requirements..."
            & $PipCmd install -r $reqPath --quiet 2>&1 | Out-Null
            Write-OK "$toolName requirements installed"
        }
    }

    $impacketDir = Join-Path $ToolsDir "impacket"
    if (Test-Path $impacketDir) {
        Write-Step "Installing impacket from source..."
        & $PipCmd install -e $impacketDir --quiet 2>&1 | Out-Null
        Write-OK "impacket installed"
    }
}

# -- Go tools --------------------------------------------------
if ($hasGo -and -not $SkipGoTools) {
    Write-Host ""
    Write-Step "Installing Go tools..."

    $goTools = @(
        @{ name = "subfinder"; pkg = "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest" },
        @{ name = "httpx";     pkg = "github.com/projectdiscovery/httpx/cmd/httpx@latest" },
        @{ name = "ffuf";      pkg = "github.com/ffuf/ffuf/v2@latest" }
    )

    foreach ($t in $goTools) {
        Write-Step "Installing $($t.name)..."
        & go install $t.pkg 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "$($t.name) installed" }
        else                     { Write-Warn "$($t.name) failed -- check Go setup" }
    }
}

# -- Launcher (.bat) -------------------------------------------
Write-Host ""
Write-Step "Creating dexter.bat launcher..."
$batContent = "@echo off`r`npowershell.exe -NoLogo -ExecutionPolicy Bypass -File `"%~dp0dexter.ps1`" %*`r`n"
$batPath = Join-Path $SCRIPT_DIR "dexter.bat"
[IO.File]::WriteAllText($batPath, $batContent, [Text.Encoding]::ASCII)
Write-OK "dexter.bat created"

$env:PATH = "$BinDir;$env:PATH"

# -- Summary ---------------------------------------------------
Write-Host ""
Write-Host ($D + "# =====================================================" + $RST)
Write-Host "  Setup complete!"
Write-Host ("  Tools dir : " + $G + $ToolsDir + $RST)
Write-Host ("  Bin dir   : " + $G + $BinDir + $RST)
if ($hasPython) {
    Write-Host ("  Python env: " + $G + (Join-Path $SCRIPT_DIR ".venv") + $RST)
}
Write-Host ($D + "# =====================================================" + $RST)
Write-Host ""
Write-Host ($G + "[+]" + $RST + " Ready! Run Dexter with:")
Write-Host ""
Write-Host ("    " + $C + ".\dexter.bat" + $RST + "   (from this directory)")
Write-Host ("    " + $C + ".\dexter.ps1" + $RST + "   (PowerShell directly)")
Write-Host ""
Write-Host "  To run from anywhere, add the toolkit dir to your PATH:"
$_q = [char]34
Write-Host ("  " + $Y + "setx PATH " + $_q + "%PATH%;" + $SCRIPT_DIR + $_q + $RST)
Write-Host ""
