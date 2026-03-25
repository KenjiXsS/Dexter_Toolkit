#Requires -Version 5.1
# ╔══════════════════════════════════════════════════════════════╗
# ║              DEXTER TOOLKIT  ·  Interactive Shell            ║
# ║              Pentest automation framework v3.0  [Windows]    ║
# ╚══════════════════════════════════════════════════════════════╝

param()

if (-not [Console]::IsInputRedirected -eq $false) {
    # allow both interactive and piped
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$SCRIPT_DIR = Split-Path -Parent (Resolve-Path $PSCommandPath)

# ─── Enable ANSI on Windows ──────────────────────────────────────────────────
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    $null = [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $h = (Get-Process -Id $PID).MainWindowHandle
        $null = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
'@ -Name 'ANSI' -Namespace 'WinConsole' -ErrorAction SilentlyContinue
        $handle = (New-Object Microsoft.Win32.SafeHandles.SafeFileHandle([IntPtr]([System.Runtime.InteropServices.Marshal]::GetHINSTANCE([System.Reflection.Assembly]::GetExecutingAssembly().GetModules()[0])), $false))
    } catch {}
    # Enable VirtualTerminalProcessing via stdout handle
    try {
        $stdout = [System.Console]::OpenStandardOutput()
        $null = $stdout
    } catch {}
}
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# ─── Colors ──────────────────────────────────────────────────────────────────
$E      = [char]27
$C_RST  = "${E}[0m";  $C_DIM  = "${E}[2m";  $C_BOLD = "${E}[1m"
$C_RED  = "${E}[31m"; $C_GRN  = "${E}[32m"; $C_YLW  = "${E}[33m"
$C_BLU  = "${E}[34m"; $C_MAG  = "${E}[35m"; $C_CYN  = "${E}[36m"
$C_BGRN = "${E}[1;32m"; $C_BCYN = "${E}[1;36m"; $C_BRED = "${E}[1;31m"
$C_BYLW = "${E}[1;33m"; $C_BMAG = "${E}[1;35m"

# ─── Tool Detection ──────────────────────────────────────────────────────────
$GoBin = ""
try {
    $gopath = & go env GOPATH 2>$null
    if ($gopath) { $GoBin = Join-Path $gopath "bin" }
}catch {}
if (-not $GoBin) { $GoBin = Join-Path $env:USERPROFILE "go\bin" }
if ($GoBin -and (Test-Path $GoBin)) {
    $env:PATH = "$GoBin;$env:PATH"
}

$PythonCmd = "python"
$PipCmd    = "pip"
$VenvDir   = Join-Path $SCRIPT_DIR ".venv"

function Test-Cmd([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Setup-Venv {
    if (-not (Test-Cmd 'python')) { return }
    if (-not (Test-Path $VenvDir)) {
        & python -m venv $VenvDir 2>$null | Out-Null
    }
    $act = Join-Path $VenvDir "Scripts\Activate.ps1"
    if (Test-Path $act) {
        . $act 2>$null
        $script:PythonCmd = Join-Path $VenvDir "Scripts\python.exe"
        $script:PipCmd    = Join-Path $VenvDir "Scripts\pip.exe"
    }
}

function Test-Xsstrike  { (Test-Path (Join-Path $SCRIPT_DIR "tools\XSStrike\xsstrike.py")) -or (Test-Cmd 'xsstrike') }
function Test-Subfinder { (Test-Cmd 'subfinder') -or (Test-Path (Join-Path $GoBin "subfinder.exe")) }
function Test-Ffuf      { (Test-Cmd 'ffuf')      -or (Test-Path (Join-Path $GoBin "ffuf.exe")) }
function Test-Httpx     { (Test-Cmd 'httpx')     -or (Test-Path (Join-Path $GoBin "httpx.exe")) }
function Test-Rustscan  { (Test-Cmd 'rustscan') }
function Test-Sqlmap    { (Test-Path (Join-Path $SCRIPT_DIR "tools\sqlmap\sqlmap.py")) -or (Test-Cmd 'sqlmap') }
function Test-Bloodhound{ (Test-Cmd 'bloodhound-python') -or (& python -c "import bloodhound" 2>$null; $LASTEXITCODE -eq 0) }
function Test-Evilwinrm { (Test-Cmd 'evil-winrm') -or (Test-Cmd 'evil_winrm') }
function Test-Impacket  { (Test-Path (Join-Path $SCRIPT_DIR "tools\impacket\examples\secretsdump.py")) -or (& python -c "import impacket" 2>$null; $LASTEXITCODE -eq 0) }
function Test-Metasploit{ (Test-Cmd 'msfconsole') -or (Test-Path "C:\metasploit-framework\bin\msfconsole.bat") }
function Test-Ligolo    { (Test-Cmd 'ligolo') -or (Test-Path (Join-Path $SCRIPT_DIR "bin\ligolo.exe")) -or (Test-Path (Join-Path $GoBin "ligolo.exe")) }
function Test-Chisel    { (Test-Cmd 'chisel') -or (Test-Path (Join-Path $SCRIPT_DIR "bin\chisel.exe")) -or (Test-Path (Join-Path $GoBin "chisel.exe")) }
function Test-Semgrep   { (Test-Cmd 'semgrep') }
function Test-Wafw00f   { (Test-Cmd 'wafw00f') }
function Test-Gitdumper { (Test-Cmd 'git-dumper') }
function Test-Wpscan    { (Test-Cmd 'wpscan') }
function Test-Cewl      { (Test-Cmd 'cewl') }
function Test-Nmap      { (Test-Cmd 'nmap') }
function Test-Curl      { (Test-Cmd 'curl') -or (Test-Cmd 'curl.exe') }
function Test-Jq        { (Test-Cmd 'jq') }

# ─── Session State ────────────────────────────────────────────────────────────
$script:SessionFile      = ""
$script:SessionDir       = ""
$script:SessionTarget    = ""
$script:SessionNotes     = @()
$script:SessionFindings  = @()
$script:SessionCommands  = @()
$script:SessionOutputs   = @()
$script:SessionStartTime = ""

# ─── Validation ──────────────────────────────────────────────────────────────
function Test-IP([string]$ip) {
    $ip = $ip -replace '/.*', ''
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    foreach ($oct in ($ip -split '\.')) { if ([int]$oct -gt 255) { return $false } }
    return $true
}
function Test-Domain([string]$d) {
    return ($d -match '^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,253}[a-zA-Z0-9])?$') -and ($d -notmatch '\.\.')
}
function Test-Url([string]$u) { return $u -match '^https?://[a-zA-Z0-9._-]' }
function Test-Target([string]$t) { return (Test-IP $t) -or (Test-Domain $t) -or (Test-Url $t) }

function Sanitize-Flags([string]$s) { return $s -replace '[^a-zA-Z0-9 ._/\-:,=+@%~\[\]{}_()"'']', '' }
function Sanitize-Dir([string]$s)   {
    $s = $s -replace 'https?://', '' -replace '/.*', ''
    $s = $s -replace '[^a-zA-Z0-9._-]', ''
    if ($s.Length -gt 64) { $s = $s.Substring(0,64) }
    return $s
}

# ─── Logging ──────────────────────────────────────────────────────────────────
function Log-Session([string]$msg) {
    $ts = Get-Date -Format 'HH:mm:ss'
    "[$ts] $msg" | Add-Content -Path $script:SessionFile -Encoding UTF8
}
function Log-Command([string]$cmd)    { Log-Session "[CMD] $cmd"; $script:SessionCommands += $cmd }
function Log-Finding([string]$f)      { $script:SessionFindings += $f; Log-Session "[FINDING] $f" }
function Log-Note([string]$n)         { $script:SessionNotes    += $n; Log-Session "[NOTE] $n" }
function Log-Output([string]$label, [string]$content) {
    $hash = ""
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        $sha   = [System.Security.Cryptography.SHA256]::Create()
        $h     = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        $hash  = " [sha256:$($h.Substring(0,16))...]"
    } catch {}
    $script:SessionOutputs += "── $label ──`n$content"
    $sep = "─" * 54
    "`n── OUTPUT: $label$hash ──$sep`n$content`n$sep`n" |
        Add-Content -Path $script:SessionFile -Encoding UTF8
}

# ─── Session Init ─────────────────────────────────────────────────────────────
function Init-Session {
    $script:SessionStartTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $script:SessionDir  = Join-Path $SCRIPT_DIR "results"
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:SessionFile = Join-Path $script:SessionDir "session_${ts}.log"
    New-Item -ItemType Directory -Path $script:SessionDir -Force | Out-Null
    @(
        "═══════════════════════════════════════════════════",
        " DEXTER SESSION LOG",
        " Started: $($script:SessionStartTime)",
        "═══════════════════════════════════════════════════",
        ""
    ) | Set-Content -Path $script:SessionFile -Encoding UTF8
    Log-Session "[SESSION STARTED]"
}

# ─── UI Helpers ───────────────────────────────────────────────────────────────
function Show-Section([string]$title) {
    $w   = 56
    $pad = [Math]::Floor(($w - $title.Length) / 2)
    $rpad= $w - $pad - $title.Length
    $line = "═" * $w
    Write-Host "`n${C_DIM}${C_GRN}╔${line}╗${C_RST}"
    Write-Host "${C_DIM}${C_GRN}║${C_RST}$(' ' * $pad)${C_BOLD}${C_BGRN}${title}${C_RST}$(' ' * $rpad)${C_DIM}${C_GRN}║${C_RST}"
    Write-Host "${C_DIM}${C_GRN}╚${line}╝${C_RST}`n"
}

function Show-Example([string]$cmd, [string]$desc="") {
    Write-Host "${C_DIM}  ┌─ example${C_RST}"
    if ($desc) { Write-Host "${C_DIM}  │  ${C_YLW}${desc}${C_RST}" }
    Write-Host "${C_DIM}  │  ${C_BCYN}`$ ${cmd}${C_RST}"
    Write-Host "${C_DIM}  └─${C_RST}"
}

function Show-RunHeader([string]$tool, [string]$cmd) {
    $line = "─" * 54
    Write-Host "`n${C_DIM}${C_GRN}┌──[ ${C_BGRN}${tool}${C_RST}${C_DIM}${C_GRN} ]${line}"
    Write-Host "│  ${C_CYN}`$ ${cmd}${C_RST}"
    Write-Host "${C_DIM}${C_GRN}└${line}────────${C_RST}`n"
}

# ─── Run tool with live output + capture ─────────────────────────────────────
function Invoke-WithCapture {
    param([string]$Tool, [string[]]$TArgs, [string]$Label, [int]$TailLines=80)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        & $Tool @TArgs 2>&1 | ForEach-Object {
            $line = if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
            Write-Host $line
            $line | Add-Content -Path $tmp -Encoding UTF8
        }
    } catch { Write-Host "${C_BRED}[✘] Error: $_${C_RST}" }
    $content = Get-Content $tmp -Raw -EA SilentlyContinue
    if ($content) {
        $lines = $content -split "`n"
        $tail  = if ($lines.Count -gt $TailLines) { ($lines | Select-Object -Last $TailLines) -join "`n" } else { $content }
        Log-Output $Label $tail
    }
    Remove-Item $tmp -Force -EA SilentlyContinue
}

# ─── Clipboard helper ────────────────────────────────────────────────────────
function Copy-ToClipboard([string]$FilePath) {
    try {
        Get-Content $FilePath -Raw | Set-Clipboard
        Write-Host "${C_BGRN}[+] Copied to clipboard${C_RST}"
    } catch {
        Write-Host "${C_DIM}[i] Set-Clipboard not available — open file manually${C_RST}"
    }
}

# ─── Banner ──────────────────────────────────────────────────────────────────
function Show-Banner {
    Write-Host "${C_BGRN}"
    Write-Host "  ██████╗ ███████╗██╗  ██╗████████╗███████╗██████╗ "
    Write-Host "  ██╔══██╗██╔════╝╚██╗██╔╝╚══██╔══╝██╔════╝██╔══██╗"
    Write-Host "  ██║  ██║█████╗   ╚███╔╝    ██║   █████╗  ██████╔╝"
    Write-Host "  ██║  ██║██╔══╝   ██╔██╗    ██║   ██╔══╝  ██╔══██╗"
    Write-Host "  ██████╔╝███████╗██╔╝ ██╗   ██║   ███████╗██║  ██║"
    Write-Host "  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝"
    Write-Host "${C_RST}"
    Write-Host "${C_DIM}${C_CYN}         ·  TONIGHT IS THE NIGHT  ·  [Windows]${C_RST}"
    Write-Host "${C_DIM}  ──────────────────────────────────────────────────${C_RST}`n"
}

# ─── Tools Menu ──────────────────────────────────────────────────────────────
function Show-ToolsMenu {
    $ok = "${C_BGRN}✔${C_RST}"; $no = "${C_DIM}${C_RED}✘${C_RST}"
    $nm = if (Test-Nmap)      { $ok } else { $no }
    $sf = if (Test-Subfinder) { $ok } else { $no }
    $rs = if (Test-Rustscan)  { $ok } else { $no }
    $hx = if (Test-Httpx)     { $ok } else { $no }
    $ff = if (Test-Ffuf)      { $ok } else { $no }
    $sq = if (Test-Sqlmap)    { $ok } else { $no }
    $xs = if (Test-Xsstrike)  { $ok } else { $no }
    $wf = if (Test-Wafw00f)   { $ok } else { $no }
    $sg = if (Test-Semgrep)   { $ok } else { $no }
    $wp = if (Test-Wpscan)    { $ok } else { $no }
    $cw = if (Test-Cewl)      { $ok } else { $no }
    $bh = if (Test-Bloodhound){ $ok } else { $no }
    $ew = if (Test-Evilwinrm) { $ok } else { $no }
    $im = if (Test-Impacket)  { $ok } else { $no }
    $ms = if (Test-Metasploit){ $ok } else { $no }
    $ch = if (Test-Chisel)    { $ok } else { $no }
    $lg = if (Test-Ligolo)    { $ok } else { $no }
    $gd = if (Test-Gitdumper) { $ok } else { $no }
    $ds = $ok  # built-in python

    Write-Host "${C_DIM}${C_CYN}╔══ RECON ══════════════════════════════════════════╗${C_RST}"
    Write-Host "  $nm nmap       $sf subfinder   $rs rustscan    $hx httpx"
    Write-Host "  $ff ffuf       $ds dirsearch   ${ok} crtsh"
    Write-Host "${C_DIM}${C_CYN}╠══ VULNERABILITIES ════════════════════════════════╣${C_RST}"
    Write-Host "  $sq sqlmap     $xs xsstrike    $wf wafw00f     $sg semgrep"
    Write-Host "  $wp wpscan     $cw cewl"
    Write-Host "${C_DIM}${C_CYN}╠══ AD / NETWORK ═══════════════════════════════════╣${C_RST}"
    Write-Host "  $bh bloodhound $ew evil-winrm  $im impacket    $ms metasploit"
    Write-Host "${C_DIM}${C_CYN}╠══ PIVOTING ════════════════════════════════════════╣${C_RST}"
    Write-Host "  $ch chisel     ${C_DIM}${C_RED}✘${C_RST} sshuttle*   $lg ligolo"
    Write-Host "${C_DIM}${C_CYN}╠══ OTHER ══════════════════════════════════════════╣${C_RST}"
    Write-Host "  ${C_DIM}${C_RED}✘${C_RST} pspy*      $gd git-dumper"
    Write-Host "${C_DIM}${C_CYN}╚═══════════════════════════════════════════════════╝${C_RST}"
    Write-Host "${C_DIM}  * Linux only tool${C_RST}"
    Write-Host "`n${C_DIM}  commands: /target  /note  /find  /context  /export  /export-json  /history  /help  /exit${C_RST}"
    Write-Host "${C_DIM}  automation: /recon-auto [target]  ·  template${C_RST}`n"
}

# ─── Help ─────────────────────────────────────────────────────────────────────
function Show-Help {
    Write-Host "`n${C_DIM}${C_GRN}╔══ HELP ══════════════════════════════════════════════╗${C_RST}"
    Write-Host "${C_BCYN}  Target management:${C_RST}"
    Write-Host "    /target <value>   — set current target (domain/IP/URL)"
    Write-Host "    /target           — show current target"
    Write-Host "`n${C_BCYN}  Session tracking:${C_RST}"
    Write-Host "    /note <text>      — add a session note"
    Write-Host "    /find <text>      — record a finding"
    Write-Host "    /context          — show full session context"
    Write-Host "    /history          — show command history"
    Write-Host "`n${C_BCYN}  Automation:${C_RST}"
    Write-Host "    /recon-auto [tgt] — chain: subfinder → httpx → nmap → dirsearch"
    Write-Host "    template          — run attack template (web-basic / ctf-web / ad-recon)"
    Write-Host "`n${C_BCYN}  Export:${C_RST}"
    Write-Host "    /export           — save full session to TXT (paste into LLM)"
    Write-Host "    /export-json      — save session as structured JSON"
    Write-Host "`n${C_BCYN}  Tools (just type the name):${C_RST}"
    Write-Host "    nmap  crtsh  subfinder  dirsearch  ffuf  httpx  rustscan"
    Write-Host "    sqlmap  xsstrike  wafw00f  semgrep  wpscan  cewl"
    Write-Host "    bloodhound  evil-winrm  impacket  metasploit"
    Write-Host "    chisel  ligolo  git-dumper"
    Write-Host "`n${C_BCYN}  Other:${C_RST}"
    Write-Host "    /clear            — clear screen"
    Write-Host "    /exit             — exit and save session"
    Write-Host "${C_DIM}${C_GRN}╚══════════════════════════════════════════════════════╝${C_RST}`n"
}

# ─── Context ──────────────────────────────────────────────────────────────────
function Show-Context {
    Write-Host "`n${C_DIM}${C_GRN}╔══ SESSION CONTEXT ════════════════════════════════╗${C_RST}"
    Write-Host "  ${C_BCYN}Target:${C_RST}  $(if ($script:SessionTarget) { $script:SessionTarget } else { '<not set>' })"
    Write-Host "  ${C_BCYN}Started:${C_RST} $($script:SessionStartTime)"
    Write-Host "  ${C_BCYN}Log:${C_RST}     $($script:SessionFile)"
    if ($script:SessionFindings.Count -gt 0) {
        Write-Host "`n  ${C_BYLW}Findings ($($script:SessionFindings.Count)):${C_RST}"
        foreach ($f in $script:SessionFindings) { Write-Host "    ${C_BYLW}▸${C_RST} $f" }
    }
    if ($script:SessionNotes.Count -gt 0) {
        Write-Host "`n  ${C_BMAG}Notes ($($script:SessionNotes.Count)):${C_RST}"
        foreach ($n in $script:SessionNotes) { Write-Host "    ${C_BMAG}▸${C_RST} $n" }
    }
    if ($script:SessionCommands.Count -gt 0) {
        Write-Host "`n  ${C_DIM}${C_CYN}Commands (last 10):${C_RST}"
        $cmds  = $script:SessionCommands
        $start = [Math]::Max(0, $cmds.Count - 10)
        for ($i = $start; $i -lt $cmds.Count; $i++) {
            Write-Host "    ${C_DIM}$($i+1).${C_RST} $($cmds[$i])"
        }
    }
    Write-Host "${C_DIM}${C_GRN}╚═══════════════════════════════════════════════════╝${C_RST}`n"
}

# ─── Export TXT ───────────────────────────────────────────────────────────────
function Export-Session {
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile = Join-Path $SCRIPT_DIR "results\dexter_export_${ts}.txt"
    New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine("═══════════════════════════════════════════════════════")
    $null = $sb.AppendLine("  DEXTER TOOLKIT — SESSION EXPORT")
    $null = $sb.AppendLine("  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $null = $sb.AppendLine("═══════════════════════════════════════════════════════")
    $null = $sb.AppendLine("TARGET:  $(if ($script:SessionTarget) { $script:SessionTarget } else { '<not set>' })")
    $null = $sb.AppendLine("STARTED: $($script:SessionStartTime)")
    $null = $sb.AppendLine("")
    if ($script:SessionFindings.Count -gt 0) {
        $null = $sb.AppendLine("── FINDINGS ────────────────────────────────────────────")
        foreach ($f in $script:SessionFindings) { $null = $sb.AppendLine("  • $f") }
        $null = $sb.AppendLine("")
    }
    if ($script:SessionNotes.Count -gt 0) {
        $null = $sb.AppendLine("── NOTES ───────────────────────────────────────────────")
        foreach ($n in $script:SessionNotes) { $null = $sb.AppendLine("  • $n") }
        $null = $sb.AppendLine("")
    }
    if ($script:SessionOutputs.Count -gt 0) {
        $null = $sb.AppendLine("── TOOL OUTPUTS ────────────────────────────────────────")
        foreach ($o in $script:SessionOutputs) { $null = $sb.AppendLine($o); $null = $sb.AppendLine("") }
    }
    $null = $sb.AppendLine("── COMMANDS RUN ────────────────────────────────────────")
    foreach ($c in $script:SessionCommands) { $null = $sb.AppendLine("  `$ $c") }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("═══════════════════════════════════════════════════════")
    $null = $sb.AppendLine("  END OF EXPORT — paste into your LLM for context")
    $null = $sb.AppendLine("═══════════════════════════════════════════════════════")
    $sb.ToString() | Set-Content -Path $outFile -Encoding UTF8
    Write-Host "`n${C_BGRN}[+] Session exported → $outFile${C_RST}"
    Copy-ToClipboard $outFile
}

# ─── Export JSON ──────────────────────────────────────────────────────────────
function Export-Json {
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile = Join-Path $SCRIPT_DIR "results\dexter_export_${ts}.json"
    New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null
    function JE([string]$s) { '"' + ($s -replace '\\','\\' -replace '"','\"' -replace "`t",'\t' -replace "`n",'\n' -replace "`r",'') + '"' }
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine("{")
    $null = $sb.AppendLine('  "tool": "dexter-toolkit",')
    $null = $sb.AppendLine("  `"target`": $(JE $script:SessionTarget),")
    $null = $sb.AppendLine("  `"started`": $(JE $script:SessionStartTime),")
    $null = $sb.AppendLine("  `"exported`": $(JE (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),")
    $null = $sb.AppendLine('  "findings": [')
    $first = $true
    foreach ($f in $script:SessionFindings) {
        if (-not $first) { $null = $sb.AppendLine(",") }
        $null = $sb.Append("    $(JE $f)"); $first = $false
    }
    $null = $sb.AppendLine("`n  ],")
    $null = $sb.AppendLine('  "notes": [')
    $first = $true
    foreach ($n in $script:SessionNotes) {
        if (-not $first) { $null = $sb.AppendLine(",") }
        $null = $sb.Append("    $(JE $n)"); $first = $false
    }
    $null = $sb.AppendLine("`n  ],")
    $null = $sb.AppendLine('  "commands": [')
    $first = $true
    foreach ($c in $script:SessionCommands) {
        if (-not $first) { $null = $sb.AppendLine(",") }
        $null = $sb.Append("    $(JE $c)"); $first = $false
    }
    $null = $sb.AppendLine("`n  ],")
    $null = $sb.AppendLine('  "outputs": [')
    $first = $true
    foreach ($o in $script:SessionOutputs) {
        if (-not $first) { $null = $sb.AppendLine(",") }
        $null = $sb.Append("    $(JE $o)"); $first = $false
    }
    $null = $sb.AppendLine("`n  ]")
    $null = $sb.AppendLine("}")
    $sb.ToString() | Set-Content -Path $outFile -Encoding UTF8
    Write-Host "`n${C_BGRN}[+] JSON exported → $outFile${C_RST}"
    Copy-ToClipboard $outFile
}

# ─── Wordlist Chooser ─────────────────────────────────────────────────────────
function Choose-Wordlist {
    $searchDirs = @(
        (Join-Path $SCRIPT_DIR "seclists"),
        (Join-Path $SCRIPT_DIR "wordlists"),
        "C:\tools\seclists",
        "C:\tools\wordlists",
        "$env:USERPROFILE\wordlists"
    )
    $wlFiles = @()
    foreach ($d in $searchDirs) {
        if (Test-Path $d) {
            $wlFiles += Get-ChildItem -Path $d -Recurse -File -ErrorAction SilentlyContinue |
                        Select-Object -First 200 -ExpandProperty FullName
        }
    }
    if ($wlFiles.Count -eq 0) {
        Write-Host "${C_YLW}[!] No wordlists found${C_RST}"
        $custom = Read-Host "  Enter full path to wordlist"
        if (Test-Path $custom) { return $custom }
        Write-Host "${C_RED}[✘] File not found${C_RST}"
        return $null
    }
    Write-Host "`n${C_DIM}  ┌─ Available wordlists (showing up to 200) ────────────${C_RST}"
    for ($i = 0; $i -lt [Math]::Min($wlFiles.Count, 200); $i++) {
        Write-Host "${C_DIM}  │  ${C_CYN}$($i+1))${C_RST} $($wlFiles[$i])"
    }
    Write-Host "${C_DIM}  │  ${C_CYN}0)${C_RST} Enter custom path"
    Write-Host "${C_DIM}  └─────────────────────────────────────────────────${C_RST}"
    while ($true) {
        $idx = Read-Host "  Choose wordlist [1-$($wlFiles.Count), 0=custom]"
        if ($idx -match '^\d+$') {
            $idx = [int]$idx
            if ($idx -eq 0) {
                $custom = Read-Host "  Full path"
                if (Test-Path $custom) { return $custom }
                Write-Host "${C_RED}  File not found.${C_RST}"
            } elseif ($idx -ge 1 -and $idx -le $wlFiles.Count) {
                return $wlFiles[$idx - 1]
            } else {
                Write-Host "${C_YLW}  Invalid index (1-$($wlFiles.Count)).${C_RST}"
            }
        } else { Write-Host "${C_YLW}  Enter a number.${C_RST}" }
    }
}

# ─── Tool: nmap ───────────────────────────────────────────────────────────────
function Run-Nmap {
    if (-not (Test-Nmap)) { Write-Host "${C_RED}[✘] nmap not installed${C_RST}"; return }
    Show-Example "nmap -sV -sC -p 22,80,443,8080 192.168.1.100"
    Show-Example "nmap -p- --min-rate 5000 -sV 10.10.11.5" "all ports fast"
    $tgt = (Read-Host "  Target (IP/domain)").Trim()
    if (-not $tgt) { Write-Host "  Cancelled."; return }
    if (-not (Test-Target $tgt)) {
        Write-Host "${C_YLW}[!] Warning: `"$tgt`" may not be a valid IP or domain.${C_RST}"
        $cont = Read-Host "  Continue anyway? (y/N)"
        if ($cont -notmatch '^[Yy]$') { return }
    }
    Write-Host "  Preset: ${C_CYN}1${C_RST}) Quick(-sV)  ${C_CYN}2${C_RST}) Deep(-A -sC -sV)  ${C_CYN}3${C_RST}) All-ports(-p-)  ${C_CYN}4${C_RST}) OS+scripts  ${C_CYN}5${C_RST}) Custom"
    $c = Read-Host "  Choice [1]"; if (-not $c) { $c = "1" }
    $opts = switch ($c) {
        "1" { "-sV" }
        "2" { "-A -sC -sV" }
        "3" { "-p- --min-rate 5000 -sV" }
        "4" { "-O -sC -sV" }
        "5" { Sanitize-Flags (Read-Host "  Custom nmap flags") }
        default { "-sV" }
    }
    $extra = (Read-Host "  Extra ports (comma list, or Enter to skip)").Trim()
    if ($extra) { $opts += " -p $extra" }
    $nmapArgs = $opts -split ' ' | Where-Object { $_ }
    $nmapArgs += $tgt
    Log-Command "nmap $opts $tgt"
    Show-RunHeader "nmap" "nmap $opts $tgt"
    Invoke-WithCapture -Tool 'nmap' -TArgs $nmapArgs -Label "nmap $tgt"
    Write-Host "`n${C_BGRN}[✔] nmap finished${C_RST}"
}

# ─── Tool: crt.sh ─────────────────────────────────────────────────────────────
function Run-Crtsh {
    if (-not (Test-Curl)) { Write-Host "${C_RED}[✘] curl not installed${C_RST}"; return }
    Show-Example "crtsh → certificate transparency lookup for subdomains"
    $d = (Read-Host "  Domain (e.g. target.com)").Trim()
    if (-not $d) { Write-Host "  Cancelled."; return }
    $d = $d -replace 'https?://', '' -replace '/.*', '' -replace '^www\.', ''
    if (-not (Test-Domain $d)) {
        Write-Host "${C_YLW}[!] Warning: `"$d`" may not be a valid domain.${C_RST}"
        $cont = Read-Host "  Continue anyway? (y/N)"
        if ($cont -notmatch '^[Yy]$') { return }
    }
    Log-Command "crt.sh $d"
    Show-RunHeader "crt.sh" "Invoke-RestMethod 'https://crt.sh/?q=%25.$d&output=json'"
    try {
        $results = Invoke-RestMethod -Uri "https://crt.sh/?q=%25.$d&output=json" -TimeoutSec 30
        $subs = $results | ForEach-Object { $_.name_value } |
                ForEach-Object { $_ -replace '\*\.', '' } |
                ForEach-Object { $_.ToLower() } | Sort-Object -Unique
        foreach ($s in $subs) { Write-Host "  $s" }
        Log-Output "crt.sh $d" ($subs -join "`n")
        Write-Host "`n${C_BGRN}[✔] crt.sh finished — $($subs.Count) results${C_RST}"
    } catch {
        Write-Host "${C_RED}[✘] crt.sh request failed: $_${C_RST}"
    }
}

# ─── Tool: subfinder ─────────────────────────────────────────────────────────
function Run-Subfinder {
    if (-not (Test-Subfinder)) {
        Write-Host "${C_RED}[✘] subfinder not installed (go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest)${C_RST}"
        return
    }
    Show-Example "subfinder -d target.com -o subdomains.txt"
    $d = (Read-Host "  Domain").Trim()
    if (-not $d) { Write-Host "  Cancelled."; return }
    $d = $d -replace 'https?://', '' -replace '^www\.', '' -replace '/.*', ''
    if (-not (Test-Domain $d)) {
        Write-Host "${C_YLW}[!] Warning: `"$d`" may not be a valid domain.${C_RST}"
        $cont = Read-Host "  Continue anyway? (y/N)"
        if ($cont -notmatch '^[Yy]$') { return }
    }
    Log-Command "subfinder -d $d"
    Show-RunHeader "subfinder" "subfinder -d $d"
    $subs = @()
    & subfinder -d $d 2>&1 | ForEach-Object {
        $line = "$_"
        if ($line -notmatch '^\[INF\]|^__|projectdiscovery|^\s*$|Current.*version|Loading.*provider|Enumerating') {
            if ($line -match "\.$d" -and $line -notmatch '^\s*\[') {
                $line = $line.Trim()
                if ($line) { $subs += $line; Write-Host "    ${C_GRN}▸${C_RST} $line" }
            }
        }
    }
    if ($subs.Count -gt 0) {
        Write-Host "${C_BGRN}[✔] Found $($subs.Count) subdomain(s)${C_RST}"
        Log-Output "subfinder $d" ($subs -join "`n")
    } else {
        Write-Host "${C_YLW}[i] No subdomains found${C_RST}"
    }
    Write-Host "`n${C_BGRN}[✔] subfinder finished${C_RST}"
}

# ─── Tool: dirsearch ─────────────────────────────────────────────────────────
function Run-Dirsearch {
    $dsPath = Join-Path $SCRIPT_DIR "tools\dirsearch\dirsearch.py"
    if (-not (Test-Path $dsPath)) {
        Write-Host "${C_RED}[✘] dirsearch not found at tools\dirsearch\${C_RST}"; return
    }
    Show-Example "dirsearch -u http://192.168.1.100 -e php,html,js,txt -t 20"
    $base  = (Read-Host "  Base URL").Trim()
    if (-not $base) { Write-Host "  Cancelled."; return }
    $exts  = Read-Host "  Extensions [php,html,js,txt]"; if (-not $exts) { $exts = "php,html,js,txt" }
    $th    = Read-Host "  Threads [10]"; if (-not $th) { $th = "10" }
    $excl  = (Read-Host "  Exclude status codes (e.g. 404,403, or Enter to skip)").Trim()
    $exclArgs = if ($excl) { @("-x", $excl) } else { @() }
    Log-Command "dirsearch -u $base -e $exts -t $th"
    Show-RunHeader "dirsearch" "dirsearch -u $base -e $exts -t $th"
    $args_ = @("-u", $base, "-e", $exts, "-t", $th) + $exclArgs
    Invoke-WithCapture -Tool $script:PythonCmd -TArgs (@($dsPath) + $args_) -Label "dirsearch $base"
    Write-Host "`n${C_BGRN}[✔] dirsearch finished${C_RST}"
}

# ─── Tool: ffuf ──────────────────────────────────────────────────────────────
function Run-Ffuf {
    if (-not (Test-Ffuf)) {
        Write-Host "${C_RED}[✘] ffuf not installed (go install github.com/ffuf/ffuf/v2@latest)${C_RST}"; return
    }
    Show-Example "ffuf -w C:\tools\wordlists\common.txt -u http://192.168.1.100/FUZZ -mc 200,301,302,403"
    $tgt = (Read-Host "  Target URL (must contain FUZZ)").Trim()
    if (-not $tgt) { Write-Host "  Cancelled."; return }
    if ($tgt -notlike "*FUZZ*") { $tgt = $tgt.TrimEnd('/') + '/FUZZ'; Write-Host "  ${C_YLW}[i] Adjusted to: $tgt${C_RST}" }
    $wl = Choose-Wordlist
    if (-not $wl) { Write-Host "${C_RED}[✘] No wordlist selected${C_RST}"; return }
    $sc    = Read-Host "  Status codes [200,301,302,403,401]"; if (-not $sc) { $sc = "200,301,302,403,401" }
    $fs    = (Read-Host "  Filter by size (or Enter to skip)").Trim()
    $th    = Read-Host "  Threads [40]"; if (-not $th) { $th = "40" }
    $vhost = (Read-Host "  Host header (or Enter to skip)").Trim()
    $cmdArgs = @("-w", $wl, "-u", $tgt, "-mc", $sc, "-t", $th, "-ac")
    if ($fs)    { $cmdArgs += @("-fs", $fs) }
    if ($vhost) { $cmdArgs += @("-H", "Host: $vhost") }
    Log-Command "ffuf -w $wl -u $tgt -mc $sc -t $th"
    Show-RunHeader "ffuf" "ffuf $($cmdArgs -join ' ')"
    Invoke-WithCapture -Tool 'ffuf' -TArgs $cmdArgs -Label "ffuf $tgt"
    Write-Host "`n${C_BGRN}[✔] ffuf finished${C_RST}"
}

# ─── Tool: httpx ─────────────────────────────────────────────────────────────
function Run-Httpx {
    if (-not (Test-Httpx)) {
        Write-Host "${C_RED}[✘] httpx not installed (go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest)${C_RST}"; return
    }
    Show-Example "httpx -u http://192.168.1.100 -title -status-code -tech-detect"
    Show-Example "httpx -l subdomains.txt -title -status-code -follow-redirects"
    $target = (Read-Host "  Target (URL, domain, or path to list)").Trim()
    if (-not $target) { Write-Host "  Cancelled."; return }
    if (-not (Test-Path $target -ErrorAction SilentlyContinue)) {
        if (-not (Test-Target ($target -replace ' ',''))) {
            Write-Host "${C_YLW}[!] Warning: may not be a valid target.${C_RST}"
            $cont = Read-Host "  Continue anyway? (y/N)"
            if ($cont -notmatch '^[Yy]$') { return }
        }
    }
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Basic  ${C_CYN}2${C_RST}) Full(title+tech+status)  ${C_CYN}3${C_RST}) Custom"
    $m = Read-Host "  Choice [2]"; if (-not $m) { $m = "2" }
    $cmdArgs = @()
    switch ($m) {
        "1" {
            $cmdArgs += if (Test-Path $target -EA SilentlyContinue) { @("-l", $target) } else { @("-u", $target) }
            $cmdArgs += @("-silent", "-status-code", "-content-length")
        }
        "3" {
            $cf = (Read-Host "  Custom flags").Trim()
            if (-not $cf) { Write-Host "  Cancelled."; return }
            Log-Command "httpx $cf"
            Show-RunHeader "httpx" "httpx $cf"
            $cfArgs = $cf -split ' ' | Where-Object { $_ }
            Invoke-WithCapture -Tool 'httpx' -TArgs $cfArgs -Label "httpx"
            Write-Host "`n${C_BGRN}[✔] httpx finished${C_RST}"
            return
        }
        default {
            $cmdArgs += if (Test-Path $target -EA SilentlyContinue) { @("-l", $target) } else { @("-u", $target) }
            $cmdArgs += @("-title", "-status-code", "-tech-detect", "-content-length", "-follow-redirects")
        }
    }
    Log-Command "httpx $($cmdArgs -join ' ')"
    Show-RunHeader "httpx" "httpx $($cmdArgs -join ' ')"
    Invoke-WithCapture -Tool 'httpx' -TArgs $cmdArgs -Label "httpx $target"
    Write-Host "`n${C_BGRN}[✔] httpx finished${C_RST}"
}

# ─── Tool: rustscan ──────────────────────────────────────────────────────────
function Run-Rustscan {
    if (-not (Test-Rustscan)) { Write-Host "${C_RED}[✘] rustscan not installed${C_RST}"; return }
    Show-Example "rustscan -a 192.168.1.100 --ulimit 5000 -- -sV -sC"
    $tgt = (Read-Host "  Target (IP/hostname)").Trim()
    if (-not $tgt) { Write-Host "  Cancelled."; return }
    if (-not (Test-Target $tgt)) {
        Write-Host "${C_YLW}[!] Warning: may not be valid.${C_RST}"
        $cont = Read-Host "  Continue anyway? (y/N)"
        if ($cont -notmatch '^[Yy]$') { return }
    }
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Quick  ${C_CYN}2${C_RST}) All+nmap  ${C_CYN}3${C_RST}) Specific ports  ${C_CYN}4${C_RST}) Custom"
    $m       = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $threads = Read-Host "  Threads [1000]"; if (-not $threads) { $threads = "1000" }
    $cmdArgs = switch ($m) {
        "1" { @("-a", $tgt, "--ulimit", "5000", "-t", $threads) }
        "2" { @("-a", $tgt, "--ulimit", "5000", "-t", $threads, "--", "-sV", "-sC") }
        "3" {
            $ports = (Read-Host "  Ports (e.g. 22,80,443)").Trim()
            if (-not $ports) { Write-Host "  Cancelled."; return }
            @("-a", $tgt, "-p", $ports, "--ulimit", "5000", "-t", $threads, "--", "-sV")
        }
        "4" {
            $cf = (Read-Host "  Custom flags").Trim()
            if (-not $cf) { Write-Host "  Cancelled."; return }
            $cf -split ' ' | Where-Object { $_ }
        }
        default { @("-a", $tgt, "--ulimit", "5000", "-t", $threads) }
    }
    Log-Command "rustscan $($cmdArgs -join ' ')"
    Show-RunHeader "rustscan" "rustscan $($cmdArgs -join ' ')"
    Invoke-WithCapture -Tool 'rustscan' -TArgs $cmdArgs -Label "rustscan $tgt"
    Write-Host "`n${C_BGRN}[✔] rustscan finished${C_RST}"
}

# ─── Tool: sqlmap ─────────────────────────────────────────────────────────────
function Run-Sqlmap {
    if (-not (Test-Sqlmap)) { Write-Host "${C_RED}[✘] sqlmap not installed${C_RST}"; return }
    Show-Example "sqlmap -u 'http://192.168.1.100/page?id=1' --batch --level=2 --risk=2"
    $url = (Read-Host "  Target URL").Trim()
    if (-not $url) { Write-Host "  Cancelled."; return }
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Basic  ${C_CYN}2${C_RST}) Dump DB  ${C_CYN}3${C_RST}) POST data  ${C_CYN}4${C_RST}) Custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $sqlmapScript = Join-Path $SCRIPT_DIR "tools\sqlmap\sqlmap.py"
    $baseCmd = if (Test-Path $sqlmapScript) { @($script:PythonCmd, $sqlmapScript) } else { @('sqlmap') }
    $extraArgs = switch ($m) {
        "1" { @("-u", $url, "--batch", "--crawl=2", "--level=2", "--risk=2") }
        "2" {
            $db = (Read-Host "  Database name (or Enter for all)").Trim()
            if ($db) { @("-u", $url, "--batch", "-D", $db, "--dump") }
            else     { @("-u", $url, "--batch", "--dbs", "--dump-all") }
        }
        "3" {
            $post = (Read-Host "  POST data (e.g. user=a&pass=b)").Trim()
            if (-not $post) { Write-Host "  Cancelled."; return }
            @("-u", $url, "--data=$post", "--batch", "--level=2", "--risk=2")
        }
        "4" {
            $cf = (Read-Host "  Custom flags").Trim()
            if (-not $cf) { Write-Host "  Cancelled."; return }
            $cf -split ' ' | Where-Object { $_ }
        }
        default { @("-u", $url, "--batch", "--crawl=2", "--level=2", "--risk=2") }
    }
    $tool = $baseCmd[0]; $tArgs = ($baseCmd | Select-Object -Skip 1) + $extraArgs
    Log-Command "sqlmap $($extraArgs -join ' ')"
    Show-RunHeader "sqlmap" "$tool $($tArgs -join ' ')"
    Write-Host "${C_YLW}[!] This can be slow...${C_RST}`n"
    Invoke-WithCapture -Tool $tool -TArgs $tArgs -Label "sqlmap $url"
    Write-Host "`n${C_BGRN}[✔] sqlmap finished${C_RST}"
}

# ─── Tool: xsstrike ──────────────────────────────────────────────────────────
function Run-Xsstrike {
    if (-not (Test-Xsstrike)) { Write-Host "${C_RED}[✘] XSStrike not found at tools\XSStrike\xsstrike.py${C_RST}"; return }
    Show-Example "xsstrike -u 'http://192.168.1.100/search?q=test'"
    $url = (Read-Host "  Target URL").Trim()
    if (-not $url) { Write-Host "  Cancelled."; return }
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Quick  ${C_CYN}2${C_RST}) Crawl  ${C_CYN}3${C_RST}) Custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $xsFile = Join-Path $SCRIPT_DIR "tools\XSStrike\xsstrike.py"
    $xArgs = switch ($m) {
        "1" { @($xsFile, "-u", $url) }
        "2" { @($xsFile, "-u", $url, "--crawl") }
        "3" {
            $cf = (Read-Host "  Custom flags").Trim()
            if (-not $cf) { Write-Host "  Cancelled."; return }
            @($xsFile) + ($cf -split ' ' | Where-Object { $_ })
        }
        default { @($xsFile, "-u", $url) }
    }
    Log-Command "xsstrike $($xArgs -join ' ')"
    Show-RunHeader "xsstrike" "$($script:PythonCmd) $($xArgs -join ' ')"
    Invoke-WithCapture -Tool $script:PythonCmd -TArgs $xArgs -Label "xsstrike $url"
    Write-Host "`n${C_BGRN}[✔] XSStrike finished${C_RST}"
}

# ─── Tool: wafw00f ───────────────────────────────────────────────────────────
function Run-Wafw00f {
    if (-not (Test-Wafw00f)) { Write-Host "${C_RED}[✘] wafw00f not installed (pip install wafw00f)${C_RST}"; return }
    Show-Example "wafw00f -a http://192.168.1.100"
    $url = (Read-Host "  Target URL").Trim()
    if (-not $url) { Write-Host "  Cancelled."; return }
    Log-Command "wafw00f -a $url"
    Show-RunHeader "wafw00f" "wafw00f -a $url"
    Invoke-WithCapture -Tool 'wafw00f' -TArgs @("-a", $url) -Label "wafw00f $url" -TailLines 30
    Write-Host "`n${C_BGRN}[✔] wafw00f finished${C_RST}"
}

# ─── Tool: wpscan ────────────────────────────────────────────────────────────
function Run-Wpscan {
    if (-not (Test-Wpscan)) { Write-Host "${C_RED}[✘] wpscan not installed (gem install wpscan)${C_RST}"; return }
    Show-Example "wpscan --url http://192.168.1.100 --enumerate u,vp,vt"
    $url = (Read-Host "  Target URL").Trim()
    if (-not $url) { Write-Host "  Cancelled."; return }
    Write-Host "  Enumerate: ${C_CYN}1${C_RST}) users+vulns  ${C_CYN}2${C_RST}) all plugins  ${C_CYN}3${C_RST}) custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $flags = switch ($m) {
        "1" { "--enumerate u,vp,vt" }
        "2" { "--enumerate ap --plugins-detection aggressive" }
        "3" { Sanitize-Flags (Read-Host "  Extra flags") }
        default { "--enumerate u,vp,vt" }
    }
    $token = (Read-Host "  WPScan API token (optional, Enter to skip)").Trim()
    if ($token) { $flags += " --api-token $token" }
    $fArgs = $flags -split ' ' | Where-Object { $_ }
    $cmdArgs = @("--url", $url) + $fArgs
    Log-Command "wpscan --url $url $flags"
    Show-RunHeader "wpscan" "wpscan $($cmdArgs -join ' ')"
    Invoke-WithCapture -Tool 'wpscan' -TArgs $cmdArgs -Label "wpscan $url" -TailLines 40
    Write-Host "`n${C_BGRN}[✔] wpscan finished${C_RST}"
}

# ─── Tool: cewl ──────────────────────────────────────────────────────────────
function Run-Cewl {
    if (-not (Test-Cewl)) { Write-Host "${C_RED}[✘] cewl not installed (gem install cewl)${C_RST}"; return }
    Show-Example "cewl http://target.com -d 2 -m 5 -w wordlist.txt"
    $url    = (Read-Host "  Target URL").Trim()
    if (-not $url) { Write-Host "  Cancelled."; return }
    $depth  = Read-Host "  Depth [-d 2]";         if (-not $depth)  { $depth  = "2" }
    $minlen = Read-Host "  Min word length [-m 5]"; if (-not $minlen) { $minlen = "5" }
    $ts     = Get-Date -Format 'HHmmss'
    $defOut = Join-Path $script:SessionDir "cewl_$(Sanitize-Dir $url)_${ts}.txt"
    $customOut = (Read-Host "  Output file [$defOut]").Trim()
    $outFile = if ($customOut) { $customOut } else { $defOut }
    Log-Command "cewl $url -d $depth -m $minlen -w $outFile"
    Show-RunHeader "cewl" "cewl $url -d $depth -m $minlen -w $outFile"
    & cewl $url -d $depth -m $minlen -w $outFile 2>&1 | ForEach-Object { Write-Host "$_" }
    if (Test-Path $outFile) {
        $count = (Get-Content $outFile).Count
        Write-Host "`n${C_BGRN}[✔] cewl finished — $count words → $outFile${C_RST}"
        Log-Output "cewl $url" "$count words saved to $outFile"
    } else {
        Write-Host "`n${C_BGRN}[✔] cewl finished${C_RST}"
    }
}

# ─── Tool: semgrep ───────────────────────────────────────────────────────────
function Run-Semgrep {
    if (-not (Test-Semgrep)) { Write-Host "${C_RED}[✘] semgrep not installed (pip install semgrep)${C_RST}"; return }
    Show-Example "semgrep --config auto C:\path\to\code"
    $target = (Read-Host "  Target path").Trim()
    if (-not $target -or -not (Test-Path $target -EA SilentlyContinue)) {
        Write-Host "  Cancelled or path not found."; return
    }
    Write-Host "  Config: ${C_CYN}1${C_RST}) auto  ${C_CYN}2${C_RST}) OWASP Top10  ${C_CYN}3${C_RST}) CI  ${C_CYN}4${C_RST}) Custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $cmdArgs = switch ($m) {
        "1" { @("--config", "auto", $target) }
        "2" { @("--config", "p/owasp-top-ten", $target) }
        "3" { @("--config", "p/ci", $target) }
        "4" {
            $cfg = (Read-Host "  Config path/URL").Trim()
            if (-not $cfg) { Write-Host "  Cancelled."; return }
            @("--config", $cfg, $target)
        }
        default { @("--config", "auto", $target) }
    }
    Log-Command "semgrep $($cmdArgs -join ' ')"
    Show-RunHeader "semgrep" "semgrep $($cmdArgs -join ' ')"
    Invoke-WithCapture -Tool 'semgrep' -TArgs $cmdArgs -Label "semgrep $target"
    Write-Host "`n${C_BGRN}[✔] semgrep finished${C_RST}"
}

# ─── Tool: bloodhound ────────────────────────────────────────────────────────
function Run-Bloodhound {
    if (-not (Test-Bloodhound)) {
        Write-Host "${C_RED}[✘] bloodhound-python not installed (pip install bloodhound)${C_RST}"; return
    }
    Show-Example "bloodhound-python -d corp.local -u jdoe -p 'Pass123!' -c all -ns 10.10.10.5"
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Collect (password)  ${C_CYN}2${C_RST}) Collect (hash)  ${C_CYN}3${C_RST}) Custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    switch ($m) {
        "1" {
            $domain = (Read-Host "  Domain").Trim();   if (-not $domain) { Write-Host "  Cancelled."; return }
            $user   = (Read-Host "  Username").Trim(); if (-not $user)   { Write-Host "  Cancelled."; return }
            $pass   = (Read-Host "  Password").Trim(); if (-not $pass)   { Write-Host "  Cancelled."; return }
            $dc     = (Read-Host "  DC IP (or Enter for auto)").Trim()
            $cmdArgs = @("-d", $domain, "-u", $user, "-p", $pass, "-c", "all")
            if ($dc) { $cmdArgs += @("-dc", $dc, "-ns", $dc) }
        }
        "2" {
            $domain = (Read-Host "  Domain").Trim();    if (-not $domain) { Write-Host "  Cancelled."; return }
            $user   = (Read-Host "  Username").Trim();  if (-not $user)   { Write-Host "  Cancelled."; return }
            $hash   = (Read-Host "  NTLM hash").Trim(); if (-not $hash)   { Write-Host "  Cancelled."; return }
            $dc     = (Read-Host "  DC IP (or Enter for auto)").Trim()
            $cmdArgs = @("-d", $domain, "-u", $user, "-hashes", ":$hash", "-c", "all")
            if ($dc) { $cmdArgs += @("-dc", $dc, "-ns", $dc) }
        }
        "3" {
            $cf = (Read-Host "  Custom flags").Trim()
            if (-not $cf) { Write-Host "  Cancelled."; return }
            $cmdArgs = $cf -split ' ' | Where-Object { $_ }
        }
        default { Write-Host "${C_RED}  Invalid choice${C_RST}"; return }
    }
    Log-Command "bloodhound-python $($cmdArgs -join ' ')"
    Show-RunHeader "bloodhound" "bloodhound-python $($cmdArgs -join ' ')"
    Invoke-WithCapture -Tool 'bloodhound-python' -TArgs $cmdArgs -Label "bloodhound"
    Write-Host "`n${C_BGRN}[✔] BloodHound finished${C_RST}"
}

# ─── Tool: evil-winrm ────────────────────────────────────────────────────────
function Run-Evilwinrm {
    if (-not (Test-Evilwinrm)) { Write-Host "${C_RED}[✘] evil-winrm not installed (gem install evil-winrm)${C_RST}"; return }
    Show-Example "evil-winrm -i 192.168.1.100 -u Administrator -p 'Password123!'"
    Show-Example "evil-winrm -i 10.10.11.5 -u jdoe -H NTLMhash"
    $target = (Read-Host "  Target IP").Trim(); if (-not $target) { Write-Host "  Cancelled."; return }
    Write-Host "  Auth: ${C_CYN}1${C_RST}) User/Pass  ${C_CYN}2${C_RST}) NTLM Hash  ${C_CYN}3${C_RST}) Custom"
    $auth = Read-Host "  Choice [1]"; if (-not $auth) { $auth = "1" }
    $port = Read-Host "  Port [5985]";  if (-not $port) { $port = "5985" }
    $baseArgs = @("-P", $port)
    $authArgs = switch ($auth) {
        "1" {
            $user = (Read-Host "  Username").Trim(); $pass = (Read-Host "  Password").Trim()
            @("-i", $target, "-u", $user, "-p", $pass)
        }
        "2" {
            $user = (Read-Host "  Username").Trim(); $hash = (Read-Host "  NTLM hash").Trim()
            @("-i", $target, "-u", $user, "-H", $hash)
        }
        "3" {
            $cf = (Read-Host "  Custom flags").Trim()
            if (-not $cf) { Write-Host "  Cancelled."; return }
            $cf -split ' ' | Where-Object { $_ }
        }
        default {
            $user = (Read-Host "  Username").Trim(); $pass = (Read-Host "  Password").Trim()
            @("-i", $target, "-u", $user, "-p", $pass)
        }
    }
    $cmdArgs = $baseArgs + $authArgs
    Log-Command "evil-winrm $($cmdArgs -join ' ')"
    Show-RunHeader "evil-winrm" "evil-winrm $($cmdArgs -join ' ')"
    Write-Host "${C_YLW}[!] Interactive session — type exit to return${C_RST}`n"
    & evil-winrm @cmdArgs
    Write-Host "`n${C_BGRN}[✔] Evil-WinRM session ended${C_RST}"
}

# ─── Tool: impacket ──────────────────────────────────────────────────────────
function Run-Impacket {
    if (-not (Test-Impacket)) { Write-Host "${C_RED}[✘] impacket not installed${C_RST}"; return }
    Show-Example "secretsdump.py domain/user:pass@192.168.1.100"
    Write-Host "  Tool: ${C_CYN}1${C_RST}) secretsdump  ${C_CYN}2${C_RST}) psexec  ${C_CYN}3${C_RST}) smbexec  ${C_CYN}4${C_RST}) wmiexec  ${C_CYN}5${C_RST}) GetNPUsers  ${C_CYN}6${C_RST}) Custom"
    $t = Read-Host "  Choice [1]"; if (-not $t) { $t = "1" }
    $scriptName = switch ($t) {
        "1" { "secretsdump.py" } "2" { "psexec.py" } "3" { "smbexec.py" }
        "4" { "wmiexec.py" }    "5" { "GetNPUsers.py" }
        "6" { (Read-Host "  Script name").Trim() }
        default { "secretsdump.py" }
    }
    if (-not $scriptName) { Write-Host "  Cancelled."; return }
    $scriptPath = $null
    foreach ($candidate in @(
        (Join-Path $SCRIPT_DIR "tools\impacket\examples\$scriptName"),
        (Join-Path $SCRIPT_DIR "tools\impacket\build\scripts-3.13\$scriptName")
    )) {
        if (Test-Path $candidate) { $scriptPath = $candidate; break }
    }
    if (-not $scriptPath) {
        # Try impacket installed in Python
        $scriptPath = $scriptName
        if (-not (Test-Cmd ($scriptName -replace '\.py',''))) {
            Write-Host "${C_RED}[✘] Script not found: $scriptName${C_RST}"; return
        }
    }
    $target = (Read-Host "  Target (domain/user:pass@host)").Trim()
    if (-not $target) { Write-Host "  Cancelled."; return }
    Log-Command "impacket $scriptName $target"
    Show-RunHeader "impacket" "$scriptName $target"
    if ($scriptPath -like "*.py") {
        Invoke-WithCapture -Tool $script:PythonCmd -TArgs @($scriptPath, $target) -Label "impacket $scriptName"
    } else {
        Invoke-WithCapture -Tool $scriptPath -TArgs @($target) -Label "impacket $scriptName"
    }
    Write-Host "`n${C_BGRN}[✔] Impacket finished${C_RST}"
}

# ─── Tool: metasploit ────────────────────────────────────────────────────────
function Run-Metasploit {
    if (-not (Test-Metasploit)) { Write-Host "${C_RED}[✘] Metasploit not installed${C_RST}"; return }
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Console  ${C_CYN}2${C_RST}) Command  ${C_CYN}3${C_RST}) Resource script"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    switch ($m) {
        "1" {
            Log-Command "msfconsole"
            Show-RunHeader "metasploit" "msfconsole -q"
            Write-Host "${C_YLW}[!] Interactive session${C_RST}`n"
            & msfconsole -q
            Write-Host "`n${C_BGRN}[✔] Metasploit closed${C_RST}"
        }
        "2" {
            $cmd = (Read-Host "  Command").Trim(); if (-not $cmd) { Write-Host "  Cancelled."; return }
            Log-Command "msf: $cmd"
            Show-RunHeader "metasploit" $cmd
            Invoke-Expression $cmd 2>&1 | ForEach-Object { Write-Host "$_" }
            Write-Host "`n${C_BGRN}[✔] Done${C_RST}"
        }
        "3" {
            $script = (Read-Host "  Resource script path").Trim()
            if (-not $script -or -not (Test-Path $script -EA SilentlyContinue)) {
                Write-Host "  Cancelled."; return
            }
            Log-Command "msfconsole -r $script"
            Show-RunHeader "metasploit" "msfconsole -r $script"
            & msfconsole -q -r $script
            Write-Host "`n${C_BGRN}[✔] Metasploit finished${C_RST}"
        }
        default { & msfconsole -q }
    }
}

# ─── Tool: chisel ─────────────────────────────────────────────────────────────
function Run-Chisel {
    if (-not (Test-Chisel)) { Write-Host "${C_RED}[✘] chisel not installed${C_RST}"; return }
    Show-Example "chisel client 10.10.10.10:8080 1080:socks" "SOCKS proxy"
    Show-Example "chisel server --reverse -p 8080" "reverse server"
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Client(fwd)  ${C_CYN}2${C_RST}) Server  ${C_CYN}3${C_RST}) Reverse  ${C_CYN}4${C_RST}) Custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $chiselExe = if (Test-Path (Join-Path $SCRIPT_DIR "bin\chisel.exe")) { Join-Path $SCRIPT_DIR "bin\chisel.exe" } else { "chisel" }
    $cmdArgs = switch ($m) {
        "1" {
            $server = (Read-Host "  Server address (host:port)").Trim(); if (-not $server) { Write-Host "  Cancelled."; return }
            $tunnel = (Read-Host "  Tunnel (e.g. 1080:socks or 8080:127.0.0.1:8080)").Trim()
            @("client", $server, $tunnel)
        }
        "2" {
            $port = Read-Host "  Listen port [8080]"; if (-not $port) { $port = "8080" }
            $rev  = Read-Host "  Allow reverse? (y/N)"
            if ($rev -match '^[Yy]$') { @("server", "--reverse", "-p", $port) } else { @("server", "-p", $port) }
        }
        "3" {
            $server  = (Read-Host "  Server (host:port)").Trim();  if (-not $server) { Write-Host "  Cancelled."; return }
            $rtunnel = (Read-Host "  Reverse tunnel (e.g. R:8888:127.0.0.1:8888)").Trim()
            @("client", $server, $rtunnel)
        }
        "4" {
            $cf = (Read-Host "  Custom flags").Trim(); if (-not $cf) { Write-Host "  Cancelled."; return }
            $cf -split ' ' | Where-Object { $_ }
        }
        default { Write-Host "${C_RED}  Invalid choice${C_RST}"; return }
    }
    Log-Command "chisel $($cmdArgs -join ' ')"
    Show-RunHeader "chisel" "$chiselExe $($cmdArgs -join ' ')"
    & $chiselExe @cmdArgs 2>&1 | ForEach-Object { Write-Host "$_" }
    Write-Host "`n${C_BGRN}[✔] chisel finished${C_RST}"
}

# ─── Tool: ligolo ─────────────────────────────────────────────────────────────
function Run-Ligolo {
    if (-not (Test-Ligolo)) { Write-Host "${C_RED}[✘] ligolo not installed${C_RST}"; return }
    Show-Example "ligolo -selfcert -connect 10.10.10.10:11601" "agent connecting back"
    Show-Example "ligolo -selfcert -laddr 0.0.0.0:11601" "start proxy listener"
    Write-Host "  Mode: ${C_CYN}1${C_RST}) Agent(connect)  ${C_CYN}2${C_RST}) Proxy(listen)  ${C_CYN}3${C_RST}) Custom"
    $m = Read-Host "  Choice [1]"; if (-not $m) { $m = "1" }
    $ligoloExe = if (Test-Path (Join-Path $SCRIPT_DIR "bin\ligolo.exe")) { Join-Path $SCRIPT_DIR "bin\ligolo.exe" } else { "ligolo" }
    switch ($m) {
        "1" {
            $proxy = (Read-Host "  Proxy address (host:port)").Trim(); if (-not $proxy) { Write-Host "  Cancelled."; return }
            Log-Command "ligolo -connect $proxy"
            Show-RunHeader "ligolo" "$ligoloExe -selfcert -connect $proxy"
            & $ligoloExe -selfcert -connect $proxy 2>&1 | ForEach-Object { Write-Host "$_" }
        }
        "2" {
            $listen = Read-Host "  Listen address [0.0.0.0:11601]"; if (-not $listen) { $listen = "0.0.0.0:11601" }
            Log-Command "ligolo -laddr $listen"
            Show-RunHeader "ligolo" "$ligoloExe -selfcert -laddr $listen"
            & $ligoloExe -selfcert -laddr $listen 2>&1 | ForEach-Object { Write-Host "$_" }
        }
        "3" {
            $cf = (Read-Host "  Custom flags").Trim(); if (-not $cf) { Write-Host "  Cancelled."; return }
            $cfArgs = $cf -split ' ' | Where-Object { $_ }
            Log-Command "ligolo $cf"
            Show-RunHeader "ligolo" "$ligoloExe $cf"
            & $ligoloExe @cfArgs 2>&1 | ForEach-Object { Write-Host "$_" }
        }
        default { Write-Host "${C_RED}  Invalid choice${C_RST}"; return }
    }
    Write-Host "`n${C_BGRN}[✔] ligolo finished${C_RST}"
}

# ─── Tool: git-dumper ────────────────────────────────────────────────────────
function Run-Gitdumper {
    if (-not (Test-Gitdumper)) {
        Write-Host "${C_RED}[✘] git-dumper not installed (pip install git-dumper)${C_RST}"; return
    }
    Show-Example "git-dumper http://192.168.1.100/.git C:\loot\repo"
    $url    = (Read-Host "  Git URL (e.g. http://192.168.1.100/.git)").Trim(); if (-not $url)    { Write-Host "  Cancelled."; return }
    $outdir = (Read-Host "  Output directory").Trim();                          if (-not $outdir) { Write-Host "  Cancelled."; return }
    Log-Command "git-dumper $url $outdir"
    Show-RunHeader "git-dumper" "git-dumper $url $outdir"
    Invoke-WithCapture -Tool 'git-dumper' -TArgs @($url, $outdir) -Label "git-dumper $url" -TailLines 40
    Write-Host "`n${C_BGRN}[✔] git-dumper finished${C_RST}"
}

# ─── Recon Auto ───────────────────────────────────────────────────────────────
function Run-ReconAuto([string]$tgt="") {
    if (-not $tgt) {
        $tgt = (Read-Host "  Target (domain/IP)").Trim()
        if (-not $tgt) { Write-Host "  Cancelled."; return }
    }
    $tgt = $tgt.Trim()
    if (-not (Test-Target $tgt)) {
        Write-Host "${C_YLW}[!] Warning: `"$tgt`" may not be a valid target.${C_RST}"
        $cont = Read-Host "  Continue anyway? (y/N)"
        if ($cont -notmatch '^[Yy]$') { return }
    }
    if (-not $script:SessionTarget) { $script:SessionTarget = $tgt }
    Write-Host "`n${C_BCYN}[*] /recon-auto → $tgt${C_RST}"
    Write-Host "${C_DIM}    Chain: subfinder → httpx → nmap → dirsearch${C_RST}`n"

    $subsFile = Join-Path $script:SessionDir "recon_${tgt}_subs.txt"

    # 1. subfinder
    if ((Test-Subfinder) -and (Test-Domain $tgt)) {
        Show-Section "Step 1/4 · subfinder"
        $subs = @()
        & subfinder -d $tgt 2>&1 | ForEach-Object {
            $line = "$_"
            if ($line -notmatch '^\[INF\]|^__|projectdiscovery|^\s*$|Current.*version|Loading.*provider|Enumerating') {
                if ($line -match "\.$tgt" -and $line -notmatch '^\s*\[') {
                    $line = $line.Trim()
                    if ($line) { $subs += $line; Write-Host "  $line" }
                }
            }
        }
        if ($subs.Count -gt 0) {
            $subs | Set-Content $subsFile -Encoding UTF8
            Log-Output "subfinder $tgt" ($subs -join "`n")
            Write-Host "${C_BGRN}[✔] $($subs.Count) subdomains → $subsFile${C_RST}"
        } else { Write-Host "${C_YLW}[i] No subdomains found${C_RST}" }
    } else { Write-Host "${C_DIM}[i] Skipping subfinder (not installed or target is IP)${C_RST}" }

    # 2. httpx
    if (Test-Httpx) {
        Show-Section "Step 2/4 · httpx"
        $tmp = [IO.Path]::GetTempFileName()
        $httpxArgs = if ((Test-Path $subsFile -EA SilentlyContinue) -and (Get-Item $subsFile -EA SilentlyContinue).Length -gt 0) {
            @("-l", $subsFile, "-title", "-status-code", "-tech-detect", "-content-length", "-silent")
        } else {
            @("-u", "http://$tgt", "-title", "-status-code", "-tech-detect", "-content-length", "-silent")
        }
        & httpx @httpxArgs 2>&1 | ForEach-Object { $line = "$_"; Write-Host $line; $line | Add-Content $tmp -Encoding UTF8 }
        $content = Get-Content $tmp -Raw -EA SilentlyContinue
        if ($content) { Log-Output "httpx auto $tgt" $content }
        Remove-Item $tmp -Force -EA SilentlyContinue
    } else { Write-Host "${C_DIM}[i] Skipping httpx (not installed)${C_RST}" }

    # 3. nmap
    Show-Section "Step 3/4 · nmap"
    Log-Command "nmap -sV -T4 $tgt"
    Invoke-WithCapture -Tool 'nmap' -TArgs @("-sV", "-T4", $tgt) -Label "nmap auto $tgt"

    # 4. dirsearch
    $dsPath = Join-Path $SCRIPT_DIR "tools\dirsearch\dirsearch.py"
    if (Test-Path $dsPath) {
        Show-Section "Step 4/4 · dirsearch"
        Log-Command "dirsearch -u http://$tgt -e php,html,js,txt -t 10"
        Invoke-WithCapture -Tool $script:PythonCmd -TArgs @($dsPath, "-u", "http://$tgt", "-e", "php,html,js,txt", "-t", "10") -Label "dirsearch auto $tgt"
    } else { Write-Host "${C_DIM}[i] Skipping dirsearch (not found at tools\dirsearch\)${C_RST}" }

    Write-Host "`n${C_BGRN}[✔] /recon-auto complete for $tgt${C_RST}"
}

# ─── Attack Templates ──────────────────────────────────────────────────────────
function Run-Template {
    Write-Host "`n${C_DIM}${C_CYN}╔══ ATTACK TEMPLATES ════════════════════════════════╗${C_RST}"
    Write-Host "  ${C_CYN}1${C_RST}) web-basic  — wafw00f + nmap + httpx + dirsearch"
    Write-Host "  ${C_CYN}2${C_RST}) ctf-web    — crtsh + subfinder + httpx + ffuf"
    Write-Host "  ${C_CYN}3${C_RST}) ad-recon   — bloodhound + evil-winrm + secretsdump"
    Write-Host "${C_DIM}${C_CYN}╚════════════════════════════════════════════════════╝${C_RST}"
    $tc = Read-Host "  Choice [1-3]"
    $tt = (Read-Host "  Target (IP/domain)").Trim()
    if (-not $tt) { Write-Host "  Cancelled."; return }
    switch ($tc) {
        "1" { Invoke-TplWebBasic $tt }
        "2" { Invoke-TplCtfWeb   $tt }
        "3" { Invoke-TplAdRecon  $tt }
        default { Write-Host "${C_YLW}[!] Invalid choice${C_RST}" }
    }
}

function Invoke-TplWebBasic([string]$tgt) {
    Write-Host "`n${C_BMAG}[TPL] web-basic: wafw00f → nmap → httpx → dirsearch${C_RST}`n"
    if (Test-Wafw00f) {
        Show-Section "wafw00f"
        Invoke-WithCapture -Tool 'wafw00f' -TArgs @("-a", "http://$tgt") -Label "wafw00f $tgt" -TailLines 20
    }
    Show-Section "nmap"
    Log-Command "nmap -sV -sC -T4 $tgt"
    Invoke-WithCapture -Tool 'nmap' -TArgs @("-sV", "-sC", "-T4", $tgt) -Label "nmap $tgt"
    if (Test-Httpx) {
        Show-Section "httpx"
        Invoke-WithCapture -Tool 'httpx' -TArgs @("-u", "http://$tgt", "-title", "-status-code", "-tech-detect", "-content-length", "-silent") -Label "httpx $tgt"
    }
    $dsPath = Join-Path $SCRIPT_DIR "tools\dirsearch\dirsearch.py"
    if (Test-Path $dsPath) {
        Show-Section "dirsearch"
        Log-Command "dirsearch -u http://$tgt -e php,html,js,txt -t 10"
        Invoke-WithCapture -Tool $script:PythonCmd -TArgs @($dsPath, "-u", "http://$tgt", "-e", "php,html,js,txt", "-t", "10") -Label "dirsearch $tgt"
    }
    Write-Host "`n${C_BGRN}[✔] web-basic complete${C_RST}"
}

function Invoke-TplCtfWeb([string]$tgt) {
    Write-Host "`n${C_BMAG}[TPL] ctf-web: crtsh → subfinder → httpx → ffuf${C_RST}`n"
    # crt.sh
    Show-Section "crt.sh"
    try {
        $results = Invoke-RestMethod -Uri "https://crt.sh/?q=%25.$tgt&output=json" -TimeoutSec 30
        $subs    = $results | ForEach-Object { $_.name_value } |
                   ForEach-Object { $_ -replace '\*\.', '' } |
                   ForEach-Object { $_.ToLower() } | Sort-Object -Unique
        foreach ($s in $subs) { Write-Host "  $s" }
        Log-Output "crt.sh $tgt" ($subs -join "`n")
    } catch { Write-Host "${C_YLW}[!] crt.sh failed${C_RST}" }

    $subsFile = Join-Path $script:SessionDir "ctf_${tgt}_subs.txt"
    if (Test-Subfinder) {
        Show-Section "subfinder"
        $subs2 = @()
        & subfinder -d $tgt -silent 2>&1 | ForEach-Object { $line = "$_".Trim(); if ($line) { $subs2 += $line; Write-Host $line } }
        if ($subs2.Count -gt 0) { $subs2 | Set-Content $subsFile -Encoding UTF8; Log-Output "subfinder $tgt" ($subs2 -join "`n") }
    }
    if (Test-Httpx) {
        Show-Section "httpx"
        $hArgs = if ((Test-Path $subsFile -EA SilentlyContinue) -and (Get-Item $subsFile -EA SilentlyContinue).Length -gt 0) {
            @("-l", $subsFile, "-title", "-status-code", "-tech-detect", "-silent")
        } else { @("-u", "http://$tgt", "-title", "-status-code", "-tech-detect", "-silent") }
        Invoke-WithCapture -Tool 'httpx' -TArgs $hArgs -Label "httpx $tgt"
    }
    if (Test-Ffuf) {
        $wl = $null
        foreach ($candidate in @(
            (Join-Path $SCRIPT_DIR "seclists\Discovery\Web-Content\common.txt"),
            (Join-Path $SCRIPT_DIR "wordlists\common.txt"),
            "C:\tools\seclists\Discovery\Web-Content\common.txt",
            "C:\tools\wordlists\dirb\common.txt"
        )) {
            if (Test-Path $candidate) { $wl = $candidate; break }
        }
        if ($wl) {
            Show-Section "ffuf"
            Log-Command "ffuf -w $wl -u http://$tgt/FUZZ -mc 200,301,302,403 -ac -t 40"
            Invoke-WithCapture -Tool 'ffuf' -TArgs @("-w", $wl, "-u", "http://$tgt/FUZZ", "-mc", "200,301,302,403", "-ac", "-t", "40") -Label "ffuf $tgt"
        } else { Write-Host "${C_YLW}[i] No wordlist found for ffuf${C_RST}" }
    }
    Write-Host "`n${C_BGRN}[✔] ctf-web complete${C_RST}"
}

function Invoke-TplAdRecon([string]$tgt) {
    Write-Host "`n${C_BMAG}[TPL] ad-recon: bloodhound → evil-winrm → secretsdump${C_RST}`n"
    $domain = (Read-Host "  Domain (e.g. corp.local)").Trim(); if (-not $domain) { return }
    $user   = (Read-Host "  Username").Trim();                  if (-not $user)   { return }
    $pass   = (Read-Host "  Password").Trim();                  if (-not $pass)   { return }
    if (Test-Bloodhound) {
        Show-Section "bloodhound"
        Invoke-WithCapture -Tool 'bloodhound-python' -TArgs @("-d", $domain, "-u", $user, "-p", $pass, "-c", "all", "-ns", $tgt) -Label "bloodhound $tgt"
    }
    if (Test-Impacket) {
        Show-Section "secretsdump"
        $sdPath = Join-Path $SCRIPT_DIR "tools\impacket\examples\secretsdump.py"
        if (Test-Path $sdPath) {
            Invoke-WithCapture -Tool $script:PythonCmd -TArgs @($sdPath, "$domain/$user:$pass@$tgt") -Label "secretsdump $tgt"
        }
    }
    if (Test-Evilwinrm) {
        Show-Section "evil-winrm"
        Write-Host "${C_YLW}[!] Launching evil-winrm interactive session${C_RST}"
        & evil-winrm -i $tgt -u $user -p $pass
    }
    Write-Host "`n${C_BGRN}[✔] ad-recon complete${C_RST}"
}

# ─── Main REPL ────────────────────────────────────────────────────────────────
function Start-Dexter {
    Init-Session
    Setup-Venv

    Clear-Host
    Show-Banner
    Show-ToolsMenu

    Write-Host "${C_DIM}  Session started: $($script:SessionStartTime)${C_RST}"
    Write-Host "${C_DIM}  Log: $($script:SessionFile)${C_RST}`n"

    # Ctrl+C handler
    [Console]::TreatControlCAsInput = $false
    $null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
        $script:SessionCommands | Out-File -Append $script:SessionFile -Encoding UTF8 -EA SilentlyContinue
    } -EA SilentlyContinue

    while ($true) {
        # Draw prompt
        $targetPart = if ($script:SessionTarget) { "─[${C_BCYN}$($script:SessionTarget)${C_DIM}${C_GRN}]" } else { "" }
        [Console]::Write("${C_DIM}${C_GRN}┌─[${C_BGRN}dx${C_DIM}${C_GRN}]${targetPart}${C_RST}`n${C_DIM}${C_GRN}└─${C_BGRN}❯${C_RST} ")
        $userInput = [Console]::ReadLine()

        if ($null -eq $userInput) { break }  # EOF / Ctrl+Z
        $userInput = $userInput.Trim()
        if (-not $userInput) { continue }

        Log-Session "[INPUT] $userInput"

        # Slash commands
        if ($userInput.StartsWith('/')) {
            $parts = $userInput -split ' ', 2
            $cmd   = $parts[0]
            $args_ = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

            switch ($cmd) {
                '/target' {
                    if (-not $args_) {
                        Write-Host "  Target: ${C_BCYN}$(if ($script:SessionTarget) { $script:SessionTarget } else { '<not set>' })${C_RST}"
                        Write-Host "  Session dir: ${C_DIM}$($script:SessionDir)${C_RST}"
                    } else {
                        $raw = $args_ -replace ' ',''
                        if (-not (Test-Target $raw)) {
                            Write-Host "${C_YLW}[!] Warning: `"$raw`" may not be a valid IP, domain, or URL.${C_RST}"
                            $cont = Read-Host "  Set anyway? (y/N)"
                            if ($cont -notmatch '^[Yy]$') { continue }
                        }
                        $script:SessionTarget = $raw
                        $tdir    = Sanitize-Dir $raw
                        $newDir  = Join-Path $SCRIPT_DIR "results\$tdir"
                        New-Item -ItemType Directory -Path $newDir -Force | Out-Null
                        $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
                        $newFile = Join-Path $newDir "session_${ts}.log"
                        if (Test-Path $script:SessionFile) { Copy-Item $script:SessionFile $newFile -Force }
                        $script:SessionFile = $newFile
                        $script:SessionDir  = $newDir
                        Log-Session "[TARGET] $raw"
                        Write-Host "  ${C_BGRN}[✔] Target set: $raw${C_RST}"
                        Write-Host "  ${C_DIM}[✔] Session dir: $($script:SessionDir)${C_RST}"
                    }
                }
                '/note' {
                    if (-not $args_) { Write-Host "  Usage: /note <text>" }
                    else { Log-Note $args_; Write-Host "  ${C_BGRN}[✔] Note saved${C_RST}" }
                }
                '/find' {
                    if (-not $args_) { Write-Host "  Usage: /find <text>" }
                    else { Log-Finding $args_; Write-Host "  ${C_BGRN}[✔] Finding recorded${C_RST}" }
                }
                '/context'     { Show-Context }
                '/export'      { Export-Session }
                '/export-json' { Export-Json }
                '/recon-auto'  { Run-ReconAuto $args_ }
                '/history' {
                    Write-Host "`n${C_BCYN}  Command history (last 20):${C_RST}"
                    $cmds  = $script:SessionCommands
                    $start = [Math]::Max(0, $cmds.Count - 20)
                    for ($i = $start; $i -lt $cmds.Count; $i++) {
                        Write-Host "  ${C_DIM}$($i+1).${C_RST} $($cmds[$i])"
                    }
                    Write-Host ""
                }
                '/clear' { Clear-Host; Show-Banner; Show-ToolsMenu }
                '/save'  { Write-Host "  ${C_BGRN}[✔] Session log → $($script:SessionFile)${C_RST}" }
                '/help'  { Show-Help }
                { $_ -in '/exit','/quit','/q' } {
                    Write-Host "`n${C_DIM}  Saving session...${C_RST}"
                    Show-Context *>> $script:SessionFile
                    Write-Host "${C_BGRN}  Log → $($script:SessionFile)${C_RST}"
                    Write-Host "${C_BCYN}  Goodbye.${C_RST}`n"
                    exit 0
                }
                default {
                    Write-Host "${C_YLW}[!] Unknown command: $cmd${C_RST}"
                    Write-Host "  Type ${C_BOLD}/help${C_RST} for available commands"
                }
            }
        } else {
            # Tool commands
            $tool = ($userInput -split ' ')[0]
            switch ($tool) {
                'nmap'                          { Run-Nmap }
                { $_ -in 'crtsh','crt.sh' }    { Run-Crtsh }
                'subfinder'                     { Run-Subfinder }
                'dirsearch'                     { Run-Dirsearch }
                'ffuf'                          { Run-Ffuf }
                'httpx'                         { Run-Httpx }
                'rustscan'                      { Run-Rustscan }
                'sqlmap'                        { Run-Sqlmap }
                'xsstrike'                      { Run-Xsstrike }
                'wafw00f'                       { Run-Wafw00f }
                'wpscan'                        { Run-Wpscan }
                'cewl'                          { Run-Cewl }
                'semgrep'                       { Run-Semgrep }
                'bloodhound'                    { Run-Bloodhound }
                { $_ -in 'evil-winrm','evilwinrm' } { Run-Evilwinrm }
                'impacket'                      { Run-Impacket }
                { $_ -in 'metasploit','msfconsole' } { Run-Metasploit }
                'chisel'                        { Run-Chisel }
                'ligolo'                        { Run-Ligolo }
                { $_ -in 'sshuttle' }           { Write-Host "${C_YLW}[!] sshuttle is Linux-only. On Windows, consider using chisel or ligolo for tunneling.${C_RST}" }
                { $_ -in 'pspy','pspy64' }      { Write-Host "${C_YLW}[!] pspy is Linux-only. On Windows, use Process Monitor (Sysinternals) for process monitoring.${C_RST}" }
                { $_ -in 'git-dumper','gitdumper' } { Run-Gitdumper }
                { $_ -in 'template','templates' }   { Run-Template }
                'clear'                         { Clear-Host; Show-Banner; Show-ToolsMenu }
                default {
                    if (Test-Cmd $tool) {
                        Log-Command $userInput
                        try {
                            $parts2  = $userInput -split ' ' | Where-Object { $_ }
                            $tool2   = $parts2[0]
                            $tArgs2  = if ($parts2.Count -gt 1) { $parts2[1..($parts2.Count-1)] } else { @() }
                            & $tool2 @tArgs2 2>&1 | ForEach-Object { Write-Host "$_" }
                        } catch { Write-Host "${C_RED}[✘] Error: $_${C_RST}" }
                    } else {
                        Write-Host "${C_YLW}[!] Unknown: $tool${C_RST} — type ${C_BOLD}/help${C_RST}"
                    }
                }
            }
        }
    }

    # On exit
    Show-Context *>> $script:SessionFile
}

# ─── Entry point ──────────────────────────────────────────────────────────────
try {
    Start-Dexter
} catch {
    Write-Host "`n${C_DIM}  Saving session...${C_RST}"
    if ($script:SessionFile -and (Test-Path (Split-Path $script:SessionFile) -EA SilentlyContinue)) {
        "[INTERRUPTED] $_" | Add-Content $script:SessionFile -Encoding UTF8 -EA SilentlyContinue
    }
}
