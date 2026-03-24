#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║              DEXTER TOOLKIT  ·  Interactive Shell            ║
# ║              Pentest automation framework v3.0               ║
# ╚══════════════════════════════════════════════════════════════╝

set -o pipefail
set -o nounset

if [[ ! -t 0 ]]; then
  echo "Error: requires an interactive terminal"
  echo "Usage: ./dexter.sh"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
set -o interactive-comments

# ─── Session State ────────────────────────────────────────────────────────────
SESSION_FILE=""
SESSION_DIR=""
SESSION_TARGET=""
SESSION_NOTES=()
SESSION_FINDINGS=()
SESSION_COMMANDS=()
SESSION_OUTPUTS=()
SESSION_START_TIME=""
HISTORY_FILE=""
HISTORY_MAX=1000

# ─── Colors ──────────────────────────────────────────────────────────────────
if tput setaf 1 >/dev/null 2>&1; then
  C_BLK="$(tput setaf 0)"
  C_RED="$(tput setaf 1)"
  C_GRN="$(tput setaf 2)"
  C_YLW="$(tput setaf 3)"
  C_BLU="$(tput setaf 4)"
  C_MAG="$(tput setaf 5)"
  C_CYN="$(tput setaf 6)"
  C_WHT="$(tput setaf 7)"
  C_BGRN="$(tput bold)$(tput setaf 2)"
  C_BCYN="$(tput bold)$(tput setaf 6)"
  C_BRED="$(tput bold)$(tput setaf 1)"
  C_BYLW="$(tput bold)$(tput setaf 3)"
  C_BMAG="$(tput bold)$(tput setaf 5)"
  C_BOLD="$(tput bold)"
  C_DIM="$(tput dim)"
  C_RST="$(tput sgr0)"
else
  C_BLK="" C_RED="" C_GRN="" C_YLW="" C_BLU="" C_MAG="" C_CYN="" C_WHT=""
  C_BGRN="" C_BCYN="" C_BRED="" C_BYLW="" C_BMAG="" C_BOLD="" C_DIM="" C_RST=""
fi

# ─── Tool Detection ──────────────────────────────────────────────────────────
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Go bin
GOBIN=""
if command_exists go; then
  GOBIN="$(go env GOBIN 2>/dev/null || echo "")"
  [[ -z "$GOBIN" ]] && GOBIN="$(go env GOPATH 2>/dev/null || echo "$HOME/go")/bin"
  [[ -d "$GOBIN" && ":$PATH:" != *":$GOBIN:"* ]] && export PATH="$GOBIN:$PATH"
fi

# Python venv
VENV_DIR="$SCRIPT_DIR/.venv"
PYTHON_CMD="python3"
PIP_CMD="pip3"

setup_venv() {
  command_exists python3 || return 1
  [[ ! -d "$VENV_DIR" ]] && python3 -m venv "$VENV_DIR" 2>/dev/null || true
  if [[ -f "$VENV_DIR/bin/activate" ]]; then
    source "$VENV_DIR/bin/activate" 2>/dev/null || true
    PYTHON_CMD="$VENV_DIR/bin/python"
    PIP_CMD="$VENV_DIR/bin/pip"
    export PYTHON_CMD PIP_CMD
  fi
}

detect_xsstrike()   { [[ -x "$SCRIPT_DIR/bin/xsstrike" ]] || [[ -f "$SCRIPT_DIR/tools/XSStrike/xsstrike.py" ]] || command_exists xsstrike; }
detect_subfinder()  { command_exists subfinder || [[ -f "$GOBIN/subfinder" ]] || [[ -f "$HOME/go/bin/subfinder" ]]; }
detect_ffuf()       { command_exists ffuf || [[ -f "$GOBIN/ffuf" ]] || [[ -f "$HOME/go/bin/ffuf" ]]; }
detect_httpx()      { command_exists httpx || [[ -f "$GOBIN/httpx" ]] || [[ -f "$HOME/go/bin/httpx" ]]; }
detect_rustscan()   { command_exists rustscan || [[ -f "/usr/local/bin/rustscan" ]]; }
detect_sqlmap()     { [[ -x "$SCRIPT_DIR/bin/sqlmap" ]] || [[ -f "$SCRIPT_DIR/tools/sqlmap/sqlmap.py" ]] || command_exists sqlmap; }
detect_bloodhound() { command_exists bloodhound-python || "$PYTHON_CMD" -c "import bloodhound" 2>/dev/null; }
detect_evilwinrm()  { command_exists evil-winrm || command_exists evil_winrm; }
detect_impacket()   { [[ -f "$SCRIPT_DIR/tools/impacket/examples/secretsdump.py" ]] || [[ -f "$SCRIPT_DIR/tools/impacket/build/scripts-3.13/secretsdump.py" ]] || "$PYTHON_CMD" -c "import impacket" 2>/dev/null; }
detect_metasploit() { command_exists msfconsole || [[ -f "/usr/bin/msfconsole" ]] || [[ -f "/opt/metasploit-framework/bin/msfconsole" ]]; }
detect_ligolo()     { command_exists ligolo || [[ -f "$GOBIN/ligolo" ]] || [[ -f "$HOME/go/bin/ligolo" ]] || [[ -f "$SCRIPT_DIR/bin/ligolo" ]]; }
detect_sshuttle()   { command_exists sshuttle || "$PYTHON_CMD" -c "import sshuttle" 2>/dev/null; }
detect_chisel()     { command_exists chisel || [[ -f "$GOBIN/chisel" ]] || [[ -f "$HOME/go/bin/chisel" ]] || [[ -f "$SCRIPT_DIR/bin/chisel" ]]; }
detect_semgrep()    { command_exists semgrep || [[ -f "$VENV_DIR/bin/semgrep" ]]; }
detect_wafw00f()    { command_exists wafw00f || [[ -f "$VENV_DIR/bin/wafw00f" ]] || [[ -f "$SCRIPT_DIR/bin/wafw00f" ]]; }
detect_pspy()       { command_exists pspy64 || [[ -f "$SCRIPT_DIR/bin/pspy64" ]] || [[ -f "$SCRIPT_DIR/tools/pspy64" ]]; }
detect_gitdumper()  { command_exists git-dumper || [[ -f "$VENV_DIR/bin/git-dumper" ]] || [[ -f "$SCRIPT_DIR/bin/git-dumper" ]]; }
detect_wpscan()     { command_exists wpscan; }
detect_cewl()       { command_exists cewl; }
detect_nmap()       { command_exists nmap; }
detect_curl()       { command_exists curl; }
detect_jq()         { command_exists jq; }

_ts() {  # tool status indicator
  if "$1" 2>/dev/null; then printf '%b✔%b' "${C_BGRN}" "${C_RST}"
  else printf '%b✘%b' "${C_DIM}${C_RED}" "${C_RST}"; fi
}

# ─── Input Validation & Sanitization ─────────────────────────────────────────
_validate_ip() {
  local ip="${1%%/*}"  # strip CIDR
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS='.'; read -ra _o <<< "$ip"
  for _oct in "${_o[@]}"; do (( _oct <= 255 )) || return 1; done
  return 0
}

_validate_domain() {
  # allow hostnames like dc01, or FQDNs like corp.local, sub.domain.tld
  [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,253}[a-zA-Z0-9])?$ ]] && [[ ! "$1" =~ \.\. ]]
}

_validate_url() {
  [[ "$1" =~ ^https?://[a-zA-Z0-9._-] ]]
}

validate_target() {
  local t="$1"
  _validate_ip "$t" || _validate_domain "$t" || _validate_url "$t"
}

# Strip shell-dangerous characters from flag strings (keep: alnum, space, - . / : , = + @ % ~ [ ] { } ( ) _ " ')
sanitize_flags() {
  printf '%s' "$1" | tr -cd 'a-zA-Z0-9 ._/-:,=+@%~[]{}_()"\x27'
}

# Make a filesystem-safe dir name from a target string
sanitize_for_dir() {
  printf '%s' "$1" | sed 's|https\?://||g; s|/.*||' | tr -cd 'a-zA-Z0-9._-' | cut -c1-64
}

# ─── Session Init ─────────────────────────────────────────────────────────────
init_session() {
  SESSION_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  SESSION_DIR="$SCRIPT_DIR/results"
  SESSION_FILE="$SESSION_DIR/session_$(date '+%Y%m%d_%H%M%S').log"
  HISTORY_FILE="$SESSION_DIR/.dexter_history"
  mkdir -p "$SESSION_DIR"

  {
    echo "═══════════════════════════════════════════════════"
    echo " DEXTER SESSION LOG"
    echo " Started: $SESSION_START_TIME"
    echo "═══════════════════════════════════════════════════"
    echo ""
  } > "$SESSION_FILE"

  export HISTFILE="$HISTORY_FILE"
  export HISTSIZE=$HISTORY_MAX
  export HISTFILESIZE=$HISTORY_MAX
  set -o history
  shopt -s histexpand 2>/dev/null || true

  if [[ -f "$HISTFILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && history -s "$line"
    done < "$HISTFILE"
  fi

  log_session "[SESSION STARTED]"
}

save_history() {
  history -a "$HISTFILE" 2>/dev/null || true
  SESSION_COMMANDS=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && SESSION_COMMANDS+=("$line")
  done < <(history 2>/dev/null | tail -n $HISTORY_MAX)
}

# ─── Logging ──────────────────────────────────────────────────────────────────
log_session() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$SESSION_FILE"; }
log_command()  { log_session "[CMD] $1"; save_history; }
log_finding()  { SESSION_FINDINGS+=("$1"); log_session "[FINDING] $1"; }
log_note()     { SESSION_NOTES+=("$1"); log_session "[NOTE] $1"; }

log_output() {
  local label="$1" content="$2"
  local _hash=""
  command_exists sha256sum && _hash=" [sha256:$(printf '%s' "$content" | sha256sum | cut -c1-16)…]"
  SESSION_OUTPUTS+=("$(printf '── %s ──\n%s' "$label" "$content")")
  {
    printf '\n── OUTPUT: %s%s ──────────────────────────────────\n' "$label" "$_hash"
    printf '%s\n' "$content"
    printf '──────────────────────────────────────────────────────\n\n'
  } >> "$SESSION_FILE"
}

# ─── UI Helpers ───────────────────────────────────────────────────────────────
# Print a boxed section header
section() {
  local title="$1"
  local w=56
  local pad=$(( (w - ${#title}) / 2 ))
  printf '\n%b╔' "${C_DIM}${C_GRN}"
  printf '═%.0s' $(seq 1 $w)
  printf '╗%b\n' "${C_RST}"
  printf '%b║%b%*s%b%s%b%*s%b║%b\n' \
    "${C_DIM}${C_GRN}" "${C_RST}" \
    $pad "" \
    "${C_BOLD}${C_BGRN}" "$title" "${C_RST}" \
    $((w - pad - ${#title})) "" \
    "${C_DIM}${C_GRN}" "${C_RST}"
  printf '%b╚' "${C_DIM}${C_GRN}"
  printf '═%.0s' $(seq 1 $w)
  printf '╝%b\n\n' "${C_RST}"
}

# Print example commands before a prompt
show_example() {
  local desc="${2:-}"
  printf '%b  ┌─ example%b\n' "${C_DIM}" "${C_RST}"
  if [[ -n "$desc" ]]; then
    printf '%b  │  %b%s%b\n' "${C_DIM}" "${C_DIM}${C_YLW}" "$desc" "${C_RST}"
  fi
  printf '%b  │  %b$ %s%b\n' "${C_DIM}" "${C_BCYN}" "$1" "${C_RST}"
  printf '%b  └─%b\n' "${C_DIM}" "${C_RST}"
}

# Print tool run header
run_header() {
  local tool="$1" cmd="$2"
  printf '\n%b┌──[ %b%s%b ]' "${C_DIM}${C_GRN}" "${C_BGRN}" "$tool" "${C_RST}${C_DIM}${C_GRN}"
  printf '──────────────────────────────────────────────────────\n'
  printf '│  %b$ %s%b\n' "${C_CYN}" "$cmd" "${C_RST}"
  printf '%b└────────────────────────────────────────────────────────────%b\n\n' "${C_DIM}${C_GRN}" "${C_RST}"
}

# ─── Banner ──────────────────────────────────────────────────────────────────
show_banner() {
  printf '%b' "${C_BGRN}"
  cat <<'BANNER'

  ██████╗ ███████╗██╗  ██╗████████╗███████╗██████╗
  ██╔══██╗██╔════╝╚██╗██╔╝╚══██╔══╝██╔════╝██╔══██╗
  ██║  ██║█████╗   ╚███╔╝    ██║   █████╗  ██████╔╝
  ██║  ██║██╔══╝   ██╔██╗    ██║   ██╔══╝  ██╔══██╗
  ██████╔╝███████╗██╔╝ ██╗   ██║   ███████╗██║  ██║
  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
BANNER
  printf '%b' "${C_RST}"
  printf '%b         ·  TONIGHT IS THE NIGHT  ·%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '%b  ──────────────────────────────────────────────────%b\n\n' "${C_DIM}" "${C_RST}"
}

# ─── Tools Menu ──────────────────────────────────────────────────────────────
show_tools_menu() {
  local nm sf rs hx ff ds sq xs wf sg wp cw bh ew im ms ch ss lg py gd

  detect_nmap       && nm="${C_BGRN}✔${C_RST}" || nm="${C_DIM}${C_RED}✘${C_RST}"
  detect_subfinder  && sf="${C_BGRN}✔${C_RST}" || sf="${C_DIM}${C_RED}✘${C_RST}"
  detect_rustscan   && rs="${C_BGRN}✔${C_RST}" || rs="${C_DIM}${C_RED}✘${C_RST}"
  detect_httpx      && hx="${C_BGRN}✔${C_RST}" || hx="${C_DIM}${C_RED}✘${C_RST}"
  detect_ffuf       && ff="${C_BGRN}✔${C_RST}" || ff="${C_DIM}${C_RED}✘${C_RST}"
  ds="${C_BGRN}✔${C_RST}"  # built-in (python)
  detect_sqlmap     && sq="${C_BGRN}✔${C_RST}" || sq="${C_DIM}${C_RED}✘${C_RST}"
  detect_xsstrike   && xs="${C_BGRN}✔${C_RST}" || xs="${C_DIM}${C_RED}✘${C_RST}"
  detect_wafw00f    && wf="${C_BGRN}✔${C_RST}" || wf="${C_DIM}${C_RED}✘${C_RST}"
  detect_semgrep    && sg="${C_BGRN}✔${C_RST}" || sg="${C_DIM}${C_RED}✘${C_RST}"
  detect_wpscan     && wp="${C_BGRN}✔${C_RST}" || wp="${C_DIM}${C_RED}✘${C_RST}"
  detect_cewl       && cw="${C_BGRN}✔${C_RST}" || cw="${C_DIM}${C_RED}✘${C_RST}"
  detect_bloodhound && bh="${C_BGRN}✔${C_RST}" || bh="${C_DIM}${C_RED}✘${C_RST}"
  detect_evilwinrm  && ew="${C_BGRN}✔${C_RST}" || ew="${C_DIM}${C_RED}✘${C_RST}"
  detect_impacket   && im="${C_BGRN}✔${C_RST}" || im="${C_DIM}${C_RED}✘${C_RST}"
  detect_metasploit && ms="${C_BGRN}✔${C_RST}" || ms="${C_DIM}${C_RED}✘${C_RST}"
  detect_chisel     && ch="${C_BGRN}✔${C_RST}" || ch="${C_DIM}${C_RED}✘${C_RST}"
  detect_sshuttle   && ss="${C_BGRN}✔${C_RST}" || ss="${C_DIM}${C_RED}✘${C_RST}"
  detect_ligolo     && lg="${C_BGRN}✔${C_RST}" || lg="${C_DIM}${C_RED}✘${C_RST}"
  detect_pspy       && py="${C_BGRN}✔${C_RST}" || py="${C_DIM}${C_RED}✘${C_RST}"
  detect_gitdumper  && gd="${C_BGRN}✔${C_RST}" || gd="${C_DIM}${C_RED}✘${C_RST}"

  printf '%b╔══ RECON ══════════════════════════════════════════╗%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '  %b nmap       %b subfinder   %b rustscan    %b httpx\n'   "$nm" "$sf" "$rs" "$hx"
  printf '  %b ffuf       %b dirsearch   %b crtsh\n'                  "$ff" "$ds" "${C_BGRN}✔${C_RST}"
  printf '%b╠══ VULNERABILITIES ════════════════════════════════╣%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '  %b sqlmap     %b xsstrike    %b wafw00f     %b semgrep\n' "$sq" "$xs" "$wf" "$sg"
  printf '  %b wpscan     %b cewl\n'                                "$wp" "$cw"
  printf '%b╠══ AD / NETWORK ═══════════════════════════════════╣%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '  %b bloodhound %b evil-winrm  %b impacket    %b metasploit\n' "$bh" "$ew" "$im" "$ms"
  printf '%b╠══ PIVOTING ════════════════════════════════════════╣%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '  %b chisel     %b sshuttle    %b ligolo\n'                 "$ch" "$ss" "$lg"
  printf '%b╠══ OTHER ══════════════════════════════════════════╣%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '  %b pspy       %b git-dumper\n'                            "$py" "$gd"
  printf '%b╚═══════════════════════════════════════════════════╝%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '\n%b  commands: /target  /note  /find  /context  /export  /export-json  /history  /help  /exit%b\n' "${C_DIM}" "${C_RST}"
  printf '%b  automation: /recon-auto [target]  ·  template%b\n' "${C_DIM}" "${C_RST}"
}

# ─── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  printf '\n%b╔══ HELP ══════════════════════════════════════════════╗%b\n' "${C_DIM}${C_GRN}" "${C_RST}"
  printf '%b  Target management:%b\n' "${C_BCYN}" "${C_RST}"
  printf '    /target <value>   — set current target (domain/IP/URL)\n'
  printf '    /target           — show current target\n'
  printf '\n%b  Session tracking:%b\n' "${C_BCYN}" "${C_RST}"
  printf '    /note <text>      — add a session note\n'
  printf '    /find <text>      — record a finding\n'
  printf '    /context          — show full session context\n'
  printf '    /history          — show command history\n'
  printf '\n%b  Automation:%b\n' "${C_BCYN}" "${C_RST}"
  printf '    /recon-auto [tgt] — chain: subfinder → httpx → nmap → dirsearch\n'
  printf '    template          — run attack template (web-basic / ctf-web / ad-recon)\n'
  printf '\n%b  Export:%b\n' "${C_BCYN}" "${C_RST}"
  printf '    /export           — save full session to TXT (paste into LLM)\n'
  printf '    /export-json      — save session as structured JSON\n'
  printf '\n%b  Tools (just type the name):%b\n' "${C_BCYN}" "${C_RST}"
  printf '    nmap  crtsh  subfinder  dirsearch  ffuf  httpx  rustscan\n'
  printf '    sqlmap  xsstrike  wafw00f  semgrep  wpscan  cewl\n'
  printf '    bloodhound  evil-winrm  impacket  metasploit\n'
  printf '    chisel  sshuttle  ligolo  pspy  git-dumper\n'
  printf '\n%b  Other:%b\n' "${C_BCYN}" "${C_RST}"
  printf '    /clear            — clear screen\n'
  printf '    /exit             — exit and save session\n'
  printf '%b╚══════════════════════════════════════════════════════╝%b\n\n' "${C_DIM}${C_GRN}" "${C_RST}"
}

# ─── Context ──────────────────────────────────────────────────────────────────
show_context() {
  printf '\n%b╔══ SESSION CONTEXT ════════════════════════════════╗%b\n' "${C_DIM}${C_GRN}" "${C_RST}"
  printf '  %bTarget:%b  %s\n'  "${C_BCYN}" "${C_RST}" "${SESSION_TARGET:-<not set>}"
  printf '  %bStarted:%b %s\n'  "${C_BCYN}" "${C_RST}" "$SESSION_START_TIME"
  printf '  %bLog:%b     %s\n'  "${C_BCYN}" "${C_RST}" "$SESSION_FILE"

  if [[ ${#SESSION_FINDINGS[@]} -gt 0 ]]; then
    printf '\n  %bFindings (%d):%b\n' "${C_BYLW}" "${#SESSION_FINDINGS[@]}" "${C_RST}"
    for f in "${SESSION_FINDINGS[@]}"; do printf '    %b▸%b %s\n' "${C_BYLW}" "${C_RST}" "$f"; done
  fi

  if [[ ${#SESSION_NOTES[@]} -gt 0 ]]; then
    printf '\n  %bNotes (%d):%b\n' "${C_BMAG}" "${#SESSION_NOTES[@]}" "${C_RST}"
    for n in "${SESSION_NOTES[@]}"; do printf '    %b▸%b %s\n' "${C_BMAG}" "${C_RST}" "$n"; done
  fi

  if [[ ${#SESSION_COMMANDS[@]} -gt 0 ]]; then
    printf '\n  %bCommands (last 10):%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
    local total="${#SESSION_COMMANDS[@]}"
    local start=$(( total > 10 ? total - 10 : 0 ))
    for ((i=start; i<total; i++)); do
      printf '    %b%d.%b %s\n' "${C_DIM}" "$((i+1))" "${C_RST}" "${SESSION_COMMANDS[$i]}"
    done
  fi
  printf '%b╚═══════════════════════════════════════════════════╝%b\n\n' "${C_DIM}${C_GRN}" "${C_RST}"
}

# ─── Export Session ──────────────────────────────────────────────────────────
export_session() {
  local export_file="$SCRIPT_DIR/results/dexter_export_$(date '+%Y%m%d_%H%M%S').txt"

  {
    echo "═══════════════════════════════════════════════════════"
    echo "  DEXTER TOOLKIT — SESSION EXPORT"
    echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "TARGET:  ${SESSION_TARGET:-<not set>}"
    echo "STARTED: $SESSION_START_TIME"
    echo ""

    if [[ ${#SESSION_FINDINGS[@]} -gt 0 ]]; then
      echo "── FINDINGS ────────────────────────────────────────────"
      for f in "${SESSION_FINDINGS[@]}"; do echo "  • $f"; done
      echo ""
    fi

    if [[ ${#SESSION_NOTES[@]} -gt 0 ]]; then
      echo "── NOTES ───────────────────────────────────────────────"
      for n in "${SESSION_NOTES[@]}"; do echo "  • $n"; done
      echo ""
    fi

    if [[ ${#SESSION_OUTPUTS[@]} -gt 0 ]]; then
      echo "── TOOL OUTPUTS ────────────────────────────────────────"
      for o in "${SESSION_OUTPUTS[@]}"; do
        echo "$o"
        echo ""
      done
    fi

    echo "── COMMANDS RUN ────────────────────────────────────────"
    grep '\[CMD\]' "$SESSION_FILE" 2>/dev/null | sed 's/\[.*\] \[CMD\] /  $ /' || true
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  END OF EXPORT — paste into your LLM for context"
    echo "═══════════════════════════════════════════════════════"
  } > "$export_file"

  printf '\n%b[+] Session exported → %s%b\n' "${C_BGRN}" "$export_file" "${C_RST}"

  # Try clipboard
  if command_exists wl-copy; then
    wl-copy < "$export_file" && printf '%b[+] Copied to clipboard (wl-copy)%b\n' "${C_BGRN}" "${C_RST}"
  elif command_exists xclip; then
    xclip -selection clipboard < "$export_file" && printf '%b[+] Copied to clipboard (xclip)%b\n' "${C_BGRN}" "${C_RST}"
  elif command_exists xsel; then
    xsel --clipboard < "$export_file" && printf '%b[+] Copied to clipboard (xsel)%b\n' "${C_BGRN}" "${C_RST}"
  else
    printf '%b[i] Install wl-copy/xclip/xsel to auto-copy to clipboard%b\n' "${C_DIM}" "${C_RST}"
  fi
  echo ""
}

# ─── Wordlist Chooser (FIXED: all display → stderr) ─────────────────────────
SECLISTS_DIR="$SCRIPT_DIR/seclists"
WORDLISTS_DIR="$SCRIPT_DIR/wordlists"
_wl_files=()

collect_wordlists() {
  _wl_files=()
  for d in "$SECLISTS_DIR" "$WORDLISTS_DIR" /usr/share/wordlists /usr/share/seclists; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' f; do
      _wl_files+=("$f")
    done < <(find "$d" -maxdepth 6 -type f -print0 2>/dev/null)
  done
}

choose_wordlist() {
  collect_wordlists

  if [[ ${#_wl_files[@]} -eq 0 ]]; then
    printf '%b[!] No wordlists found in seclists/ or wordlists/%b\n' "${C_YLW}" "${C_RST}" >&2
    read -r -p "    Enter full path to wordlist: " _custom_wl
    if [[ -f "$_custom_wl" ]]; then
      printf '%s' "$_custom_wl"
      return 0
    else
      printf '%b[✘] File not found%b\n' "${C_RED}" "${C_RST}" >&2
      return 1
    fi
  fi

  local max=200 i=0
  printf '\n%b  ┌─ Available wordlists (showing up to %d) ────────────%b\n' "${C_DIM}" "$max" "${C_RST}" >&2
  for f in "${_wl_files[@]}"; do
    ((i++))
    printf '%b  │  %b%4d)%b %s\n' "${C_DIM}" "${C_CYN}" "$i" "${C_RST}" "$f" >&2
    ((i == max)) && break
  done
  printf '%b  │  %b   0)%b Enter custom path\n' "${C_DIM}" "${C_CYN}" "${C_RST}" >&2
  printf '%b  └─────────────────────────────────────────────────%b\n' "${C_DIM}" "${C_RST}" >&2

  local idx total="${#_wl_files[@]}"
  while true; do
    read -r -p "  Choose wordlist [1-${total}, 0=custom]: " idx
    if [[ "$idx" =~ ^[0-9]+$ ]]; then
      if [[ "$idx" -eq 0 ]]; then
        read -r -p "  Full path: " _custom_wl
        if [[ -f "$_custom_wl" ]]; then
          printf '%s' "$_custom_wl"
          return 0
        else
          printf '%b  File not found.%b\n' "${C_RED}" "${C_RST}" >&2
        fi
      elif (( idx >= 1 && idx <= total )); then
        printf '%s' "${_wl_files[idx-1]}"
        return 0
      else
        printf '%b  Invalid index (1-%d).%b\n' "${C_YLW}" "$total" "${C_RST}" >&2
      fi
    else
      printf '%b  Enter a number.%b\n' "${C_YLW}" "${C_RST}" >&2
    fi
  done
}

# ─── Tool: nmap ───────────────────────────────────────────────────────────────
run_nmap() {
  if ! detect_nmap; then printf '%b[✘] nmap not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "nmap -sV -sC -p 22,80,443,8080 192.168.1.100"
  show_example "nmap -p- --min-rate 5000 -sV 10.10.11.5" "all ports fast"

  read -r -p "  Target (IP/domain): " TGT
  [[ -z "$TGT" ]] && { echo "  Cancelled."; return; }
  TGT="${TGT// /}"
  if ! validate_target "$TGT"; then
    printf '%b[!] Warning: "%s" may not be a valid IP or domain.%b\n' "${C_YLW}" "$TGT" "${C_RST}"
    read -r -p "  Continue anyway? (y/N): " _cont
    [[ ! "$_cont" =~ ^[Yy]$ ]] && return
  fi

  printf '  Preset: %b1%b) Quick(-sV)  %b2%b) Deep(-A -sC -sV)  %b3%b) All-ports(-p-)  %b4%b) OS+scripts  %b5%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " c; c="${c:-1}"

  case $c in
    1) OPTS="-sV" ;;
    2) OPTS="-A -sC -sV" ;;
    3) OPTS="-p- --min-rate 5000 -sV" ;;
    4) OPTS="-O -sC -sV" ;;
    5) read -r -p "  Custom nmap flags: " OPTS; OPTS="$(sanitize_flags "$OPTS")" ;;
    *) OPTS="-sV" ;;
  esac

  read -r -p "  Extra ports (comma list, or Enter to skip): " EXTRA
  EXTRA="$(sanitize_flags "${EXTRA:-}")"
  [[ -n "$EXTRA" ]] && OPTS="$OPTS -p $EXTRA"

  local NMAP_ARGS=()
  read -ra NMAP_ARGS <<< "$OPTS"
  log_command "nmap $OPTS $TGT"
  run_header "nmap" "nmap $OPTS $TGT"

  local _tmp; _tmp=$(mktemp)
  nmap "${NMAP_ARGS[@]}" "$TGT" 2>&1 | tee "$_tmp"
  log_output "nmap $TGT" "$(tail -60 "$_tmp")"
  rm -f "$_tmp"

  printf '\n%b[✔] nmap finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: crt.sh ────────────────────────────────────────────────────────────
run_crtsh() {
  if ! detect_curl; then printf '%b[✘] curl not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "crt.sh → certificate transparency lookup for subdomains"

  read -r -p "  Domain (e.g. target.com): " D
  [[ -z "$D" ]] && { echo "  Cancelled."; return; }
  D="${D// /}"; D="${D#http://}"; D="${D#https://}"; D="${D%%/*}"
  if ! _validate_domain "$D"; then
    printf '%b[!] Warning: "%s" may not be a valid domain.%b\n' "${C_YLW}" "$D" "${C_RST}"
    read -r -p "  Continue anyway? (y/N): " _cont
    [[ ! "$_cont" =~ ^[Yy]$ ]] && return
  fi

  log_command "crt.sh $D"
  run_header "crt.sh" "curl 'https://crt.sh/?q=%.${D}&output=json'"

  local _tmp; _tmp=$(mktemp)
  if detect_jq; then
    curl -s "https://crt.sh/?q=%25.$D&output=json" \
      | jq -r '.[].name_value' 2>/dev/null \
      | sed 's/\*\.//g' | tr '[:upper:]' '[:lower:]' | sort -u \
      | awk '{print "  " $0}' \
      | tee "$_tmp"
  else
    curl -s "https://crt.sh/?q=%25.$D&output=json" \
      | sed -n 's/.*"name_value":[ ]*"\([^"]*\)".*/\1/p' \
      | sed 's/\*\.//g' | tr '[:upper:]' '[:lower:]' | sort -u \
      | awk '{print "  " $0}' \
      | tee "$_tmp"
  fi

  log_output "crt.sh $D" "$(cat "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] crt.sh finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: subfinder ─────────────────────────────────────────────────────────
run_subfinder() {
  if ! detect_subfinder; then printf '%b[✘] subfinder not installed (go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "subfinder -d target.com -o subdomains.txt"

  read -r -p "  Domain: " d
  [[ -z "$d" ]] && { echo "  Cancelled."; return; }
  d="${d// /}"; d="${d#http://}"; d="${d#https://}"; d="${d#www.}"; d="${d%/}"; d="${d%%/*}"
  if ! _validate_domain "$d"; then
    printf '%b[!] Warning: "%s" may not be a valid domain.%b\n' "${C_YLW}" "$d" "${C_RST}"
    read -r -p "  Continue anyway? (y/N): " _cont
    [[ ! "$_cont" =~ ^[Yy]$ ]] && return
  fi

  log_command "subfinder -d $d"
  run_header "subfinder" "subfinder -d $d"

  local subdomains=()
  while IFS= read -r line; do
    [[ "$line" =~ ^\[INF\] || "$line" =~ ^__ || "$line" =~ projectdiscovery || \
       "$line" =~ ^[[:space:]]*$ || "$line" =~ Current.*version || \
       "$line" =~ Loading.*provider || "$line" =~ Enumerating ]] && continue
    if [[ "$line" == *".$d" && ! "$line" =~ ^[[:space:]]*\[ ]]; then
      line="${line//[[:space:]]/}"
      [[ -n "$line" ]] && subdomains+=("$line")
    fi
  done < <(subfinder -d "$d" 2>&1)

  if [[ ${#subdomains[@]} -gt 0 ]]; then
    printf '%b[✔] Found %d subdomain(s):%b\n' "${C_BGRN}" "${#subdomains[@]}" "${C_RST}"
    for sub in "${subdomains[@]}"; do printf '    %b▸%b %s\n' "${C_GRN}" "${C_RST}" "$sub"; done
    log_output "subfinder $d" "$(printf '%s\n' "${subdomains[@]}")"
  else
    printf '%b[i] No subdomains found%b\n' "${C_YLW}" "${C_RST}"
  fi
  printf '\n%b[✔] subfinder finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: dirsearch ─────────────────────────────────────────────────────────
run_dirsearch() {
  local DIRSEARCH_PY="$SCRIPT_DIR/tools/dirsearch/dirsearch.py"
  if [[ ! -f "$DIRSEARCH_PY" ]]; then
    printf '%b[✘] dirsearch not found at tools/dirsearch/%b\n' "${C_RED}" "${C_RST}"; return
  fi

  show_example "dirsearch -u http://192.168.1.100 -e php,html,js,txt -t 20"
  show_example "dirsearch -u http://10.10.11.5:8080 -e php,bak,zip -x 404,403"

  read -r -p "  Base URL: " base
  [[ -z "$base" ]] && { echo "  Cancelled."; return; }
  read -r -p "  Extensions [php,html,js,txt]: " exts; exts="${exts:-php,html,js,txt}"
  read -r -p "  Threads [10]: " th; th="${th:-10}"
  read -r -p "  Exclude status codes (e.g. 404,403, or Enter to skip): " excl
  local excl_flag=()
  [[ -n "$excl" ]] && excl_flag=(-x "$excl")

  log_command "dirsearch -u $base -e $exts -t $th"
  run_header "dirsearch" "dirsearch -u $base -e $exts -t $th"

  local _tmp; _tmp=$(mktemp)
  "$PYTHON_CMD" "$DIRSEARCH_PY" -u "$base" -e "$exts" -t "$th" "${excl_flag[@]}" 2>&1 | tee "$_tmp"
  log_output "dirsearch $base" "$(tail -80 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] dirsearch finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: ffuf ──────────────────────────────────────────────────────────────
run_ffuf() {
  if ! detect_ffuf; then printf '%b[✘] ffuf not installed (go install github.com/ffuf/ffuf/v2@latest)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "ffuf -w /path/wordlist.txt -u http://192.168.1.100/FUZZ -mc 200,301,302,403"
  show_example "ffuf -w wl.txt -u http://10.10.11.5/FUZZ -H 'Host: FUZZ.target.com' -mc 200"

  read -r -p "  Target URL (must contain FUZZ, e.g. http://192.168.1.100/FUZZ): " tgt
  [[ -z "$tgt" ]] && { echo "  Cancelled."; return; }
  if [[ "$tgt" != *FUZZ* ]]; then
    tgt="${tgt%/}/FUZZ"
    printf '  %b[i] Adjusted to: %s%b\n' "${C_YLW}" "$tgt" "${C_RST}"
  fi

  local WL
  WL="$(choose_wordlist)" || { printf '%b[✘] Wordlist selection cancelled%b\n' "${C_RED}" "${C_RST}"; return; }
  [[ -z "$WL" ]] && { printf '%b[✘] No wordlist selected%b\n' "${C_RED}" "${C_RST}"; return; }

  read -r -p "  Status codes to match [200,301,302,403,401]: " sc; sc="${sc:-200,301,302,403,401}"
  read -r -p "  Filter by size (or Enter to skip): " fs
  read -r -p "  Threads [40]: " th; th="${th:-40}"
  read -r -p "  Host header (or Enter to skip): " vhost

  local FS_FLAG=()
  [[ -n "$fs" ]] && FS_FLAG=(-fs "$fs")

  local CMD=(ffuf -w "$WL" -u "$tgt" -mc "$sc" "${FS_FLAG[@]}" -t "$th" -ac)
  [[ -n "$vhost" ]] && CMD+=(-H "Host: $vhost")

  log_command "ffuf -w $WL -u $tgt -mc $sc -t $th"
  run_header "ffuf" "${CMD[*]}"

  local _tmp; _tmp=$(mktemp)
  "${CMD[@]}" 2>&1 | tee "$_tmp"
  log_output "ffuf $tgt" "$(tail -80 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] ffuf finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: httpx ─────────────────────────────────────────────────────────────
run_httpx() {
  if ! detect_httpx; then printf '%b[✘] httpx not installed (go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "httpx -u http://192.168.1.100 -title -status-code -tech-detect"
  show_example "httpx -l subdomains.txt -title -status-code -follow-redirects"

  read -r -p "  Target (URL, domain, or path to list): " target
  [[ -z "$target" ]] && { echo "  Cancelled."; return; }
  if [[ ! -f "$target" ]]; then
    local _t="${target// /}"
    if ! validate_target "$_t"; then
      printf '%b[!] Warning: "%s" may not be a valid URL, domain, or IP.%b\n' "${C_YLW}" "$_t" "${C_RST}"
      read -r -p "  Continue anyway? (y/N): " _cont
      [[ ! "$_cont" =~ ^[Yy]$ ]] && return
    fi
  fi

  printf '  Mode: %b1%b) Basic  %b2%b) Full(title+tech+status)  %b3%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [2]: " m; m="${m:-2}"

  local CMD=(httpx)
  case $m in
    1)
      [[ -f "$target" ]] && CMD+=(-l "$target") || CMD+=(-u "$target")
      CMD+=(-silent -status-code -content-length)
      ;;
    3)
      read -r -p "  Custom flags: " cf
      [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      log_command "httpx $cf"
      run_header "httpx" "httpx $cf"
      local _tmp; _tmp=$(mktemp)
      httpx $cf 2>&1 | tee "$_tmp"
      log_output "httpx" "$(tail -80 "$_tmp")"
      rm -f "$_tmp"
      printf '\n%b[✔] httpx finished%b\n' "${C_BGRN}" "${C_RST}"
      return
      ;;
    *)
      [[ -f "$target" ]] && CMD+=(-l "$target") || CMD+=(-u "$target")
      CMD+=(-title -status-code -tech-detect -content-length -follow-redirects)
      ;;
  esac

  log_command "httpx ${CMD[*]}"
  run_header "httpx" "${CMD[*]}"

  local _tmp; _tmp=$(mktemp)
  "${CMD[@]}" 2>&1 | tee "$_tmp"
  log_output "httpx $target" "$(tail -80 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] httpx finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: rustscan ──────────────────────────────────────────────────────────
run_rustscan() {
  if ! detect_rustscan; then printf '%b[✘] rustscan not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "rustscan -a 192.168.1.100 --ulimit 5000 -- -sV -sC"
  show_example "rustscan -a 10.10.11.5 -p 80,443,8080 --ulimit 5000 -- -sV"

  read -r -p "  Target (IP/hostname): " TGT
  [[ -z "$TGT" ]] && { echo "  Cancelled."; return; }
  TGT="${TGT// /}"
  if ! validate_target "$TGT"; then
    printf '%b[!] Warning: "%s" may not be a valid IP or hostname.%b\n' "${C_YLW}" "$TGT" "${C_RST}"
    read -r -p "  Continue anyway? (y/N): " _cont
    [[ ! "$_cont" =~ ^[Yy]$ ]] && return
  fi

  printf '  Mode: %b1%b) Quick  %b2%b) All+nmap  %b3%b) Specific ports  %b4%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"
  read -r -p "  Threads [1000]: " threads; threads="${threads:-1000}"

  local CMD=(rustscan)
  case $m in
    1) CMD+=(-a "$TGT" --ulimit 5000 -t "$threads") ;;
    2) CMD+=(-a "$TGT" --ulimit 5000 -t "$threads" -- -sV -sC) ;;
    3)
      read -r -p "  Ports (e.g. 22,80,443): " ports
      [[ -z "$ports" ]] && { echo "  Cancelled."; return; }
      CMD+=(-a "$TGT" -p "$ports" --ulimit 5000 -t "$threads" -- -sV)
      ;;
    4)
      read -r -p "  Custom flags: " cf
      [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      CMD+=($cf)
      ;;
    *) CMD+=(-a "$TGT" --ulimit 5000 -t "$threads") ;;
  esac

  log_command "rustscan ${CMD[*]}"
  run_header "rustscan" "${CMD[*]}"

  local _tmp; _tmp=$(mktemp)
  "${CMD[@]}" 2>&1 | tee "$_tmp"
  log_output "rustscan $TGT" "$(tail -60 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] rustscan finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: sqlmap ─────────────────────────────────────────────────────────────
run_sqlmap() {
  if ! detect_sqlmap; then printf '%b[✘] sqlmap not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "sqlmap -u 'http://192.168.1.100/page?id=1' --batch --level=2 --risk=2"
  show_example "sqlmap -u 'http://10.10.11.5/login' --data='user=a&pass=b' --batch --dbs"

  read -r -p "  Target URL: " url
  [[ -z "$url" ]] && { echo "  Cancelled."; return; }

  printf '  Mode: %b1%b) Basic  %b2%b) Dump DB  %b3%b) POST data  %b4%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  local CMD
  if [[ -x "$SCRIPT_DIR/bin/sqlmap" ]]; then CMD=("$PYTHON_CMD" "$SCRIPT_DIR/bin/sqlmap")
  elif [[ -f "$SCRIPT_DIR/tools/sqlmap/sqlmap.py" ]]; then CMD=("$PYTHON_CMD" "$SCRIPT_DIR/tools/sqlmap/sqlmap.py")
  else CMD=(sqlmap); fi

  case $m in
    1) CMD+=(-u "$url" --batch --crawl=2 --level=2 --risk=2) ;;
    2)
      read -r -p "  Database name (or Enter for all): " db
      if [[ -n "$db" ]]; then CMD+=(-u "$url" --batch -D "$db" --dump)
      else CMD+=(-u "$url" --batch --dbs --dump-all); fi
      ;;
    3)
      read -r -p "  POST data (e.g. user=a&pass=b): " postdata
      [[ -z "$postdata" ]] && { echo "  Cancelled."; return; }
      CMD+=(-u "$url" --data="$postdata" --batch --level=2 --risk=2)
      ;;
    4)
      read -r -p "  Custom flags: " cf
      [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      CMD+=($cf)
      ;;
    *) CMD+=(-u "$url" --batch --crawl=2 --level=2 --risk=2) ;;
  esac

  log_command "sqlmap ${CMD[*]}"
  run_header "sqlmap" "${CMD[*]}"
  printf '%b[!] This can be slow...%b\n\n' "${C_YLW}" "${C_RST}"

  local _tmp; _tmp=$(mktemp)
  "${CMD[@]}" 2>&1 | tee "$_tmp"
  log_output "sqlmap $url" "$(tail -80 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] sqlmap finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: xsstrike ──────────────────────────────────────────────────────────
run_xsstrike() {
  if ! detect_xsstrike; then printf '%b[✘] XSStrike not found at XSStrike/xsstrike.py%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "xsstrike -u 'http://192.168.1.100/search?q=test'"
  show_example "xsstrike -u 'http://10.10.11.5/search?q=test' --crawl"

  read -r -p "  Target URL: " url
  [[ -z "$url" ]] && { echo "  Cancelled."; return; }

  printf '  Mode: %b1%b) Quick  %b2%b) Crawl  %b3%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  local XS_FILE
  if [[ -x "$SCRIPT_DIR/bin/xsstrike" ]]; then XS_FILE="$SCRIPT_DIR/bin/xsstrike"
  else XS_FILE="$SCRIPT_DIR/tools/XSStrike/xsstrike.py"; fi
  local CMD=("$PYTHON_CMD" "$XS_FILE")

  case $m in
    1) CMD+=(-u "$url") ;;
    2) CMD+=(-u "$url" --crawl) ;;
    3)
      read -r -p "  Custom flags: " cf
      [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      CMD+=($cf)
      ;;
    *) CMD+=(-u "$url") ;;
  esac

  log_command "xsstrike ${CMD[*]}"
  run_header "xsstrike" "${CMD[*]}"

  local _tmp; _tmp=$(mktemp)
  "${CMD[@]}" 2>&1 | tee "$_tmp"
  log_output "xsstrike $url" "$(tail -60 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] XSStrike finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: wafw00f ───────────────────────────────────────────────────────────
run_wafw00f() {
  if ! detect_wafw00f; then printf '%b[✘] wafw00f not installed (pip install wafw00f)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "wafw00f -a http://192.168.1.100"
  show_example "wafw00f -a https://target.com"

  read -r -p "  Target URL: " url
  [[ -z "$url" ]] && { echo "  Cancelled."; return; }

  log_command "wafw00f -a $url"
  run_header "wafw00f" "wafw00f -a $url"

  local _tmp; _tmp=$(mktemp)
  wafw00f -a "$url" 2>&1 | tee "$_tmp"
  log_output "wafw00f $url" "$(tail -30 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] wafw00f finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: wpscan ────────────────────────────────────────────────────────────
run_wpscan() {
  if ! detect_wpscan; then printf '%b[✘] wpscan not installed (gem install wpscan)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "wpscan --url http://192.168.1.100 --enumerate u,vp,vt"
  show_example "wpscan --url https://target.com --enumerate ap --plugins-detection aggressive"

  read -r -p "  Target URL: " url
  [[ -z "$url" ]] && { echo "  Cancelled."; return; }

  printf '  Enumerate: %b1%b) users+vulns (default)  %b2%b) all plugins  %b3%b) custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  local flags=""
  case $m in
    1) flags="--enumerate u,vp,vt" ;;
    2) flags="--enumerate ap --plugins-detection aggressive" ;;
    3)
      read -r -p "  Extra flags: " flags
      flags="$(sanitize_flags "$flags")"
      ;;
    *) flags="--enumerate u,vp,vt" ;;
  esac

  local api_token=""
  read -r -p "  WPScan API token (optional, Enter to skip): " api_token
  [[ -n "$api_token" ]] && flags="$flags --api-token $api_token"

  local cmd="wpscan --url $url $flags"
  log_command "$cmd"
  run_header "wpscan" "$cmd"

  local _tmp; _tmp=$(mktemp)
  # shellcheck disable=SC2086
  wpscan --url "$url" $flags 2>&1 | tee "$_tmp"
  log_output "wpscan $url" "$(tail -40 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] wpscan finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: cewl ──────────────────────────────────────────────────────────────
run_cewl() {
  if ! detect_cewl; then printf '%b[✘] cewl not installed (gem install cewl)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "cewl http://target.com -d 2 -m 5 -w wordlist.txt"
  show_example "cewl https://target.com -d 3 -m 4 --email -w words.txt"

  read -r -p "  Target URL: " url
  [[ -z "$url" ]] && { echo "  Cancelled."; return; }

  read -r -p "  Depth [-d 2]: " depth; depth="${depth:-2}"
  read -r -p "  Min word length [-m 5]: " minlen; minlen="${minlen:-5}"

  local outfile="$SESSION_DIR/cewl_$(sanitize_for_dir "$url")_$(date '+%H%M%S').txt"
  read -r -p "  Output file [$outfile]: " custom_out
  [[ -n "$custom_out" ]] && outfile="$custom_out"

  local cmd="cewl $url -d $depth -m $minlen -w $outfile"
  log_command "$cmd"
  run_header "cewl" "$cmd"

  cewl "$url" -d "$depth" -m "$minlen" -w "$outfile" 2>&1
  if [[ -f "$outfile" ]]; then
    local count; count=$(wc -l < "$outfile")
    printf '\n%b[✔] cewl finished — %s words → %s%b\n' "${C_BGRN}" "$count" "$outfile" "${C_RST}"
    log_output "cewl $url" "$count words saved to $outfile"
  else
    printf '\n%b[✔] cewl finished%b\n' "${C_BGRN}" "${C_RST}"
  fi
}

# ─── Tool: semgrep ───────────────────────────────────────────────────────────
run_semgrep() {
  if ! detect_semgrep; then printf '%b[✘] semgrep not installed (pip install semgrep)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "semgrep --config auto /path/to/code"
  show_example "semgrep --config p/owasp-top-ten /path/to/code"

  read -r -p "  Target path: " target
  [[ -z "$target" || ! -e "$target" ]] && { echo "  Cancelled."; return; }

  printf '  Config: %b1%b) auto  %b2%b) OWASP Top10  %b3%b) CI  %b4%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  local CMD=(semgrep)
  case $m in
    1) CMD+=(--config auto "$target") ;;
    2) CMD+=(--config p/owasp-top-ten "$target") ;;
    3) CMD+=(--config p/ci "$target") ;;
    4)
      read -r -p "  Config path/URL: " cfg
      [[ -z "$cfg" ]] && { echo "  Cancelled."; return; }
      CMD+=(--config "$cfg" "$target")
      ;;
    *) CMD+=(--config auto "$target") ;;
  esac

  log_command "semgrep ${CMD[*]}"
  run_header "semgrep" "${CMD[*]}"

  local _tmp; _tmp=$(mktemp)
  "${CMD[@]}" 2>&1 | tee "$_tmp"
  log_output "semgrep $target" "$(tail -80 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] semgrep finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: bloodhound ────────────────────────────────────────────────────────
run_bloodhound() {
  if ! detect_bloodhound; then printf '%b[✘] bloodhound-python not installed (pip install bloodhound)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "bloodhound-python -d corp.local -u jdoe -p 'Pass123!' -c all -ns 10.10.10.5"
  show_example "bloodhound-python -d corp.local -u jdoe -hashes :NTLMhash -c all"

  printf '  Mode: %b1%b) Collect (password)  %b2%b) Collect (hash)  %b3%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  case $m in
    1)
      read -r -p "  Domain: " domain; [[ -z "$domain" ]] && { echo "  Cancelled."; return; }
      read -r -p "  Username: " user;  [[ -z "$user"   ]] && { echo "  Cancelled."; return; }
      read -r -p "  Password: " pass;  [[ -z "$pass"   ]] && { echo "  Cancelled."; return; }
      read -r -p "  DC IP (or Enter for auto): " dc_ip
      local CMD=(bloodhound-python -d "$domain" -u "$user" -p "$pass" -c all)
      [[ -n "$dc_ip" ]] && CMD+=(-dc "$dc_ip" -ns "$dc_ip")
      ;;
    2)
      read -r -p "  Domain: " domain; [[ -z "$domain" ]] && { echo "  Cancelled."; return; }
      read -r -p "  Username: " user;  [[ -z "$user"   ]] && { echo "  Cancelled."; return; }
      read -r -p "  NTLM hash: " hash; [[ -z "$hash"   ]] && { echo "  Cancelled."; return; }
      read -r -p "  DC IP (or Enter for auto): " dc_ip
      local CMD=(bloodhound-python -d "$domain" -u "$user" -hashes ":$hash" -c all)
      [[ -n "$dc_ip" ]] && CMD+=(-dc "$dc_ip" -ns "$dc_ip")
      ;;
    3)
      read -r -p "  Custom flags: " cf
      [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      local CMD=(bloodhound-python $cf)
      ;;
    *) printf '%b  Invalid choice%b\n' "${C_RED}" "${C_RST}"; return ;;
  esac

  log_command "bloodhound-python ${CMD[*]}"
  run_header "bloodhound" "${CMD[*]}"
  "${CMD[@]}" 2>&1
  printf '\n%b[✔] BloodHound finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: evil-winrm ────────────────────────────────────────────────────────
run_evilwinrm() {
  if ! detect_evilwinrm; then printf '%b[✘] evil-winrm not installed (gem install evil-winrm)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "evil-winrm -i 192.168.1.100 -u Administrator -p 'Password123!'"
  show_example "evil-winrm -i 10.10.11.5 -u jdoe -H aad3b435b51404eeaad3b435b51404ee:NTLMhash"

  read -r -p "  Target IP: " target; [[ -z "$target" ]] && { echo "  Cancelled."; return; }

  printf '  Auth: %b1%b) User/Pass  %b2%b) NTLM Hash  %b3%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " auth; auth="${auth:-1}"
  read -r -p "  Port [5985]: " port; port="${port:-5985}"

  local CMD=(evil-winrm -P "$port")
  case $auth in
    1)
      read -r -p "  Username: " user; read -r -p "  Password: " pass
      CMD+=(-i "$target" -u "$user" -p "$pass")
      ;;
    2)
      read -r -p "  Username: " user; read -r -p "  NTLM hash: " hash
      CMD+=(-i "$target" -u "$user" -H "$hash")
      ;;
    3)
      read -r -p "  Custom flags: " cf
      [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      CMD+=($cf)
      ;;
    *) read -r -p "  Username: " user; read -r -p "  Password: " pass
       CMD+=(-i "$target" -u "$user" -p "$pass") ;;
  esac

  log_command "evil-winrm ${CMD[*]}"
  run_header "evil-winrm" "${CMD[*]}"
  printf '%b[!] Interactive session — type exit to return%b\n\n' "${C_YLW}" "${C_RST}"
  "${CMD[@]}" 2>&1
  printf '\n%b[✔] Evil-WinRM session ended%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: impacket ──────────────────────────────────────────────────────────
run_impacket() {
  if ! detect_impacket; then printf '%b[✘] impacket not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "secretsdump.py domain/user:pass@192.168.1.100"
  show_example "psexec.py domain/Administrator:Pass@10.10.11.5"

  printf '  Tool: %b1%b) secretsdump  %b2%b) psexec  %b3%b) smbexec  %b4%b) wmiexec  %b5%b) GetNPUsers  %b6%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " tool; tool="${tool:-1}"

  local script_name
  case $tool in
    1) script_name="secretsdump.py" ;;
    2) script_name="psexec.py" ;;
    3) script_name="smbexec.py" ;;
    4) script_name="wmiexec.py" ;;
    5) script_name="GetNPUsers.py" ;;
    6) read -r -p "  Script name: " script_name; [[ -z "$script_name" ]] && { echo "  Cancelled."; return; } ;;
    *) script_name="secretsdump.py" ;;
  esac

  local script_path=""
  for _candidate in \
    "$SCRIPT_DIR/tools/impacket/examples/$script_name" \
    "$SCRIPT_DIR/tools/impacket/build/scripts-3.13/$script_name"; do
    [[ -f "$_candidate" ]] && { script_path="$_candidate"; break; }
  done
  if [[ -z "$script_path" ]]; then
    printf '%b[✘] Script not found: %s/tools/impacket/.../%s%b\n' "${C_RED}" "$SCRIPT_DIR" "$script_name" "${C_RST}"; return
  fi

  read -r -p "  Target (domain/user:pass@host): " target
  [[ -z "$target" ]] && { echo "  Cancelled."; return; }

  log_command "impacket $script_name $target"
  run_header "impacket" "$script_name $target"

  local _tmp; _tmp=$(mktemp)
  "$PYTHON_CMD" "$script_path" "$target" 2>&1 | tee "$_tmp"
  log_output "impacket $script_name" "$(tail -60 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] Impacket finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: metasploit ────────────────────────────────────────────────────────
run_metasploit() {
  if ! detect_metasploit; then printf '%b[✘] Metasploit not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  printf '  Mode: %b1%b) Console  %b2%b) Command  %b3%b) Resource script\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  case $m in
    1)
      log_command "msfconsole"
      run_header "metasploit" "msfconsole -q"
      printf '%b[!] Interactive session%b\n\n' "${C_YLW}" "${C_RST}"
      msfconsole -q
      printf '\n%b[✔] Metasploit closed%b\n' "${C_BGRN}" "${C_RST}"
      ;;
    2)
      read -r -p "  Command: " cmd; [[ -z "$cmd" ]] && { echo "  Cancelled."; return; }
      log_command "msf: $cmd"
      run_header "metasploit" "$cmd"
      sh -c "$cmd" 2>&1
      printf '\n%b[✔] Done%b\n' "${C_BGRN}" "${C_RST}"
      ;;
    3)
      read -r -p "  Resource script path: " script
      [[ -z "$script" || ! -f "$script" ]] && { echo "  Cancelled."; return; }
      log_command "msfconsole -r $script"
      run_header "metasploit" "msfconsole -r $script"
      msfconsole -q -r "$script"
      printf '\n%b[✔] Metasploit finished%b\n' "${C_BGRN}" "${C_RST}"
      ;;
    *) log_command "msfconsole"; msfconsole -q ;;
  esac
}

# ─── Tool: chisel ─────────────────────────────────────────────────────────────
run_chisel() {
  if ! detect_chisel; then printf '%b[✘] chisel not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "chisel client 10.10.10.10:8080 1080:socks" "SOCKS proxy"
  show_example "chisel server --reverse -p 8080" "reverse server"
  show_example "chisel client 10.10.10.10:8080 R:8888:127.0.0.1:8888" "reverse port forward"

  printf '  Mode: %b1%b) Client(fwd)  %b2%b) Server  %b3%b) Reverse  %b4%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  local CMD=(chisel)
  case $m in
    1)
      read -r -p "  Server address (host:port): " server; [[ -z "$server" ]] && { echo "  Cancelled."; return; }
      read -r -p "  Tunnel (e.g. 1080:socks or 8080:127.0.0.1:8080): " tunnel
      CMD+=(client "$server" "$tunnel")
      ;;
    2)
      read -r -p "  Listen port [8080]: " port; port="${port:-8080}"
      read -r -p "  Allow reverse? (y/N): " rev
      if [[ "$rev" =~ ^[Yy]$ ]]; then CMD+=(server --reverse -p "$port")
      else CMD+=(server -p "$port"); fi
      ;;
    3)
      read -r -p "  Server (host:port): " server; [[ -z "$server" ]] && { echo "  Cancelled."; return; }
      read -r -p "  Reverse tunnel (e.g. R:8888:127.0.0.1:8888): " rtunnel
      CMD+=(client "$server" "$rtunnel")
      ;;
    4)
      read -r -p "  Custom flags: " cf; [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      CMD+=($cf)
      ;;
    *) printf '%b  Invalid choice%b\n' "${C_RED}" "${C_RST}"; return ;;
  esac

  log_command "chisel ${CMD[*]}"
  run_header "chisel" "${CMD[*]}"
  "${CMD[@]}" 2>&1
  printf '\n%b[✔] chisel finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: sshuttle ──────────────────────────────────────────────────────────
run_sshuttle() {
  if ! detect_sshuttle; then printf '%b[✘] sshuttle not installed (pip install sshuttle)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "sshuttle -r user@10.10.10.10 192.168.1.0/24" "route specific subnet"
  show_example "sshuttle -r user@10.10.10.10 0.0.0.0/0" "route all traffic"

  printf '  Mode: %b1%b) Full tunnel  %b2%b) Specific subnet  %b3%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  case $m in
    1)
      read -r -p "  SSH server (user@host): " server; [[ -z "$server" ]] && { echo "  Cancelled."; return; }
      read -r -p "  Networks [0.0.0.0/0]: " networks; networks="${networks:-0.0.0.0/0}"
      log_command "sshuttle -r $server $networks"
      run_header "sshuttle" "sshuttle -r $server $networks"
      sshuttle -r "$server" $networks 2>&1
      ;;
    2)
      read -r -p "  SSH server (user@host): " server; [[ -z "$server" ]] && { echo "  Cancelled."; return; }
      read -r -p "  Networks (space/comma separated): " networks; [[ -z "$networks" ]] && { echo "  Cancelled."; return; }
      local nets; nets=$(echo "$networks" | tr ',' ' ')
      log_command "sshuttle -r $server $nets"
      run_header "sshuttle" "sshuttle -r $server $nets"
      sshuttle -r "$server" $nets 2>&1
      ;;
    3)
      read -r -p "  Custom flags: " cf; [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      log_command "sshuttle $cf"
      run_header "sshuttle" "sshuttle $cf"
      sshuttle $cf 2>&1
      ;;
    *) printf '%b  Invalid choice%b\n' "${C_RED}" "${C_RST}"; return ;;
  esac
  printf '\n%b[✔] sshuttle finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: ligolo ─────────────────────────────────────────────────────────────
run_ligolo() {
  if ! detect_ligolo; then printf '%b[✘] ligolo not installed%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "ligolo -selfcert -connect 10.10.10.10:11601" "agent connecting back"
  show_example "ligolo -selfcert -laddr 0.0.0.0:11601" "start proxy listener"

  printf '  Mode: %b1%b) Agent(connect)  %b2%b) Proxy(listen)  %b3%b) Custom\n' \
    "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}" "${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1]: " m; m="${m:-1}"

  case $m in
    1)
      read -r -p "  Proxy address (host:port): " proxy; [[ -z "$proxy" ]] && { echo "  Cancelled."; return; }
      log_command "ligolo -connect $proxy"
      run_header "ligolo" "ligolo -selfcert -connect $proxy"
      ligolo -selfcert -connect "$proxy" 2>&1
      ;;
    2)
      read -r -p "  Listen address [0.0.0.0:11601]: " listen; listen="${listen:-0.0.0.0:11601}"
      log_command "ligolo -laddr $listen"
      run_header "ligolo" "ligolo -selfcert -laddr $listen"
      ligolo -selfcert -laddr "$listen" 2>&1
      ;;
    3)
      read -r -p "  Custom flags: " cf; [[ -z "$cf" ]] && { echo "  Cancelled."; return; }
      log_command "ligolo $cf"
      run_header "ligolo" "ligolo $cf"
      ligolo $cf 2>&1
      ;;
    *) printf '%b  Invalid choice%b\n' "${C_RED}" "${C_RST}"; return ;;
  esac
  printf '\n%b[✔] ligolo finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: pspy ───────────────────────────────────────────────────────────────
run_pspy() {
  if ! detect_pspy; then
    printf '%b[✘] pspy64 not found%b\n  Put it in %s/bin/pspy64\n' "${C_RED}" "${C_RST}" "$SCRIPT_DIR"
    return
  fi

  show_example "pspy64  →  monitors processes without root privileges" ""
  printf '%b[i] Press Ctrl+C to stop%b\n\n' "${C_YLW}" "${C_RST}"

  log_command "pspy64"
  run_header "pspy" "pspy64"
  pspy64 2>&1
  printf '\n%b[✔] pspy finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Tool: git-dumper ────────────────────────────────────────────────────────
run_gitdumper() {
  if ! detect_gitdumper; then printf '%b[✘] git-dumper not installed (pip install git-dumper)%b\n' "${C_RED}" "${C_RST}"; return; fi

  show_example "git-dumper http://192.168.1.100/.git /tmp/dumped_repo"
  show_example "git-dumper http://10.10.11.5/.git ./loot/repo"

  read -r -p "  Git URL (e.g. http://192.168.1.100/.git): " url
  [[ -z "$url" ]] && { echo "  Cancelled."; return; }
  read -r -p "  Output directory: " outdir
  [[ -z "$outdir" ]] && { echo "  Cancelled."; return; }

  log_command "git-dumper $url $outdir"
  run_header "git-dumper" "git-dumper $url $outdir"

  local _tmp; _tmp=$(mktemp)
  git-dumper "$url" "$outdir" 2>&1 | tee "$_tmp"
  log_output "git-dumper $url" "$(tail -40 "$_tmp")"
  rm -f "$_tmp"
  printf '\n%b[✔] git-dumper finished%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Recon Auto ───────────────────────────────────────────────────────────────
# /recon-auto <target>  →  subfinder → httpx → nmap → dirsearch
run_recon_auto() {
  local tgt="${1:-}"
  if [[ -z "$tgt" ]]; then
    read -r -p "  Target (domain/IP): " tgt
    [[ -z "$tgt" ]] && { echo "  Cancelled."; return; }
  fi
  tgt="${tgt// /}"
  if ! validate_target "$tgt"; then
    printf '%b[!] Warning: "%s" may not be a valid target.%b\n' "${C_YLW}" "$tgt" "${C_RST}"
    read -r -p "  Continue anyway? (y/N): " _cont
    [[ ! "$_cont" =~ ^[Yy]$ ]] && return
  fi

  [[ -z "$SESSION_TARGET" ]] && SESSION_TARGET="$tgt"
  printf '\n%b[*] /recon-auto → %s%b\n' "${C_BCYN}" "$tgt" "${C_RST}"
  printf '%b    Chain: subfinder → httpx → nmap → dirsearch%b\n\n' "${C_DIM}" "${C_RST}"

  local _subs_file="$SESSION_DIR/recon_${tgt}_subs.txt"

  # 1. subfinder (domain only)
  if detect_subfinder && _validate_domain "$tgt"; then
    section "Step 1/4 · subfinder"
    local subdomains=()
    while IFS= read -r line; do
      [[ "$line" =~ ^\[INF\] || "$line" =~ ^__ || "$line" =~ projectdiscovery || \
         "$line" =~ ^[[:space:]]*$ || "$line" =~ "Current.*version" || \
         "$line" =~ "Loading.*provider" || "$line" =~ "Enumerating" ]] && continue
      if [[ "$line" == *".$tgt" && ! "$line" =~ ^[[:space:]]*\[ ]]; then
        line="${line//[[:space:]]/}"
        [[ -n "$line" ]] && subdomains+=("$line")
      fi
    done < <(subfinder -d "$tgt" 2>&1)
    if [[ ${#subdomains[@]} -gt 0 ]]; then
      printf '%s\n' "${subdomains[@]}" | tee "$_subs_file"
      log_output "subfinder $tgt" "$(printf '%s\n' "${subdomains[@]}")"
      printf '%b[✔] %d subdomains → %s%b\n' "${C_BGRN}" "${#subdomains[@]}" "$_subs_file" "${C_RST}"
    else
      printf '%b[i] No subdomains found%b\n' "${C_YLW}" "${C_RST}"
    fi
  else
    printf '%b[i] Skipping subfinder (not installed or target is IP)%b\n' "${C_DIM}" "${C_RST}"
  fi

  # 2. httpx
  if detect_httpx; then
    section "Step 2/4 · httpx"
    local _tmp; _tmp=$(mktemp)
    if [[ -f "$_subs_file" && -s "$_subs_file" ]]; then
      httpx -l "$_subs_file" -title -status-code -tech-detect -content-length -silent 2>&1 | tee "$_tmp"
    else
      httpx -u "http://$tgt" -title -status-code -tech-detect -content-length -silent 2>&1 | tee "$_tmp"
    fi
    log_output "httpx auto $tgt" "$(cat "$_tmp")"
    rm -f "$_tmp"
  else
    printf '%b[i] Skipping httpx (not installed)%b\n' "${C_DIM}" "${C_RST}"
  fi

  # 3. nmap
  section "Step 3/4 · nmap"
  local _tmp; _tmp=$(mktemp)
  log_command "nmap -sV -T4 $tgt"
  nmap -sV -T4 "$tgt" 2>&1 | tee "$_tmp"
  log_output "nmap auto $tgt" "$(tail -60 "$_tmp")"
  rm -f "$_tmp"

  # 4. dirsearch
  local DIRSEARCH_PY="$SCRIPT_DIR/tools/dirsearch/dirsearch.py"
  if [[ -f "$DIRSEARCH_PY" ]]; then
    section "Step 4/4 · dirsearch"
    local _tmp; _tmp=$(mktemp)
    log_command "dirsearch -u http://$tgt -e php,html,js,txt -t 10"
    "$PYTHON_CMD" "$DIRSEARCH_PY" -u "http://$tgt" -e "php,html,js,txt" -t 10 2>&1 | tee "$_tmp"
    log_output "dirsearch auto $tgt" "$(tail -60 "$_tmp")"
    rm -f "$_tmp"
  else
    printf '%b[i] Skipping dirsearch (not found at tools/dirsearch/)%b\n' "${C_DIM}" "${C_RST}"
  fi

  printf '\n%b[✔] /recon-auto complete for %s%b\n' "${C_BGRN}" "$tgt" "${C_RST}"
}

# ─── Attack Templates ──────────────────────────────────────────────────────────
run_template() {
  printf '\n%b╔══ ATTACK TEMPLATES ════════════════════════════════╗%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  printf '  %b1%b) web-basic  — wafw00f + nmap + httpx + dirsearch\n' "${C_CYN}" "${C_RST}"
  printf '  %b2%b) ctf-web    — crtsh + subfinder + httpx + ffuf\n' "${C_CYN}" "${C_RST}"
  printf '  %b3%b) ad-recon   — bloodhound + evil-winrm + secretsdump\n' "${C_CYN}" "${C_RST}"
  printf '%b╚════════════════════════════════════════════════════╝%b\n' "${C_DIM}${C_CYN}" "${C_RST}"
  read -r -p "  Choice [1-3]: " _tc
  read -r -p "  Target (IP/domain): " _tt
  [[ -z "$_tt" ]] && { echo "  Cancelled."; return; }
  [[ -z "$SESSION_TARGET" ]] && SESSION_TARGET="$_tt"
  case "$_tc" in
    1) _tpl_web_basic "$_tt" ;;
    2) _tpl_ctf_web   "$_tt" ;;
    3) _tpl_ad_recon  "$_tt" ;;
    *) printf '%b[!] Invalid choice%b\n' "${C_YLW}" "${C_RST}" ;;
  esac
}

_tpl_web_basic() {
  local tgt="$1"
  printf '\n%b[TPL] web-basic: wafw00f → nmap → httpx → dirsearch%b\n\n' "${C_BMAG}" "${C_RST}"

  if detect_wafw00f; then
    section "wafw00f"; local _tmp; _tmp=$(mktemp)
    log_command "wafw00f -a http://$tgt"
    wafw00f -a "http://$tgt" 2>&1 | tee "$_tmp"
    log_output "wafw00f $tgt" "$(tail -20 "$_tmp")"; rm -f "$_tmp"
  fi

  section "nmap"; local _tmp; _tmp=$(mktemp)
  log_command "nmap -sV -sC -T4 $tgt"
  nmap -sV -sC -T4 "$tgt" 2>&1 | tee "$_tmp"
  log_output "nmap $tgt" "$(tail -60 "$_tmp")"; rm -f "$_tmp"

  if detect_httpx; then
    section "httpx"; local _tmp; _tmp=$(mktemp)
    httpx -u "http://$tgt" -title -status-code -tech-detect -content-length -silent 2>&1 | tee "$_tmp"
    log_output "httpx $tgt" "$(cat "$_tmp")"; rm -f "$_tmp"
  fi

  local DIRSEARCH_PY="$SCRIPT_DIR/tools/dirsearch/dirsearch.py"
  if [[ -f "$DIRSEARCH_PY" ]]; then
    section "dirsearch"; local _tmp; _tmp=$(mktemp)
    log_command "dirsearch -u http://$tgt -e php,html,js,txt -t 10"
    "$PYTHON_CMD" "$DIRSEARCH_PY" -u "http://$tgt" -e "php,html,js,txt" -t 10 2>&1 | tee "$_tmp"
    log_output "dirsearch $tgt" "$(tail -60 "$_tmp")"; rm -f "$_tmp"
  fi

  printf '\n%b[✔] web-basic complete%b\n' "${C_BGRN}" "${C_RST}"
}

_tpl_ctf_web() {
  local tgt="$1"
  printf '\n%b[TPL] ctf-web: crtsh → subfinder → httpx → ffuf%b\n\n' "${C_BMAG}" "${C_RST}"

  if detect_curl; then
    section "crt.sh"; local _tmp; _tmp=$(mktemp)
    if detect_jq; then
      curl -s "https://crt.sh/?q=%25.$tgt&output=json" \
        | jq -r '.[].name_value' 2>/dev/null \
        | sed 's/\*\.//g' | tr '[:upper:]' '[:lower:]' | sort -u | awk '{print "  "$0}' | tee "$_tmp"
    else
      curl -s "https://crt.sh/?q=%25.$tgt&output=json" \
        | sed -n 's/.*"name_value":[ ]*"\([^"]*\)".*/\1/p' \
        | sed 's/\*\.//g' | tr '[:upper:]' '[:lower:]' | sort -u | awk '{print "  "$0}' | tee "$_tmp"
    fi
    log_output "crt.sh $tgt" "$(cat "$_tmp")"; rm -f "$_tmp"
  fi

  local _subs_file="$SESSION_DIR/ctf_${tgt}_subs.txt"
  if detect_subfinder; then
    section "subfinder"
    subfinder -d "$tgt" -silent 2>/dev/null | tee "$_subs_file"
    log_output "subfinder $tgt" "$(cat "$_subs_file" 2>/dev/null)"
  fi

  if detect_httpx; then
    section "httpx"; local _tmp; _tmp=$(mktemp)
    if [[ -f "$_subs_file" && -s "$_subs_file" ]]; then
      httpx -l "$_subs_file" -title -status-code -tech-detect -silent 2>&1 | tee "$_tmp"
    else
      httpx -u "http://$tgt" -title -status-code -tech-detect -silent 2>&1 | tee "$_tmp"
    fi
    log_output "httpx $tgt" "$(cat "$_tmp")"; rm -f "$_tmp"
  fi

  if detect_ffuf; then
    local WL=""
    for _wl in \
      "$SECLISTS_DIR/Discovery/Web-Content/common.txt" \
      "$WORDLISTS_DIR/common.txt" \
      /usr/share/seclists/Discovery/Web-Content/common.txt \
      /usr/share/wordlists/dirb/common.txt; do
      [[ -f "$_wl" ]] && { WL="$_wl"; break; }
    done
    if [[ -n "$WL" ]]; then
      section "ffuf"; local _tmp; _tmp=$(mktemp)
      log_command "ffuf -w $WL -u http://$tgt/FUZZ -mc 200,301,302,403 -ac -t 40"
      ffuf -w "$WL" -u "http://$tgt/FUZZ" -mc "200,301,302,403" -ac -t 40 2>&1 | tee "$_tmp"
      log_output "ffuf $tgt" "$(tail -60 "$_tmp")"; rm -f "$_tmp"
    else
      printf '%b[i] No wordlist found for ffuf — run ffuf manually%b\n' "${C_YLW}" "${C_RST}"
    fi
  fi

  printf '\n%b[✔] ctf-web complete%b\n' "${C_BGRN}" "${C_RST}"
}

_tpl_ad_recon() {
  local tgt="$1"
  printf '\n%b[TPL] ad-recon: bloodhound → evil-winrm → secretsdump%b\n\n' "${C_BMAG}" "${C_RST}"
  printf '%b[i] Each tool requires the same credentials — enter them once:%b\n\n' "${C_YLW}" "${C_RST}"

  read -r -p "  Domain (e.g. corp.local): " domain; [[ -z "$domain" ]] && { echo "  Cancelled."; return; }
  read -r -p "  Username: " user;               [[ -z "$user" ]]   && { echo "  Cancelled."; return; }
  read -r -s -p "  Password: " pass; echo "";   [[ -z "$pass" ]]   && { echo "  Cancelled."; return; }

  if detect_bloodhound; then
    section "bloodhound"
    local CMD=(bloodhound-python -d "$domain" -u "$user" -p "$pass" -c all -ns "$tgt")
    log_command "bloodhound-python -d $domain -u $user -c all -ns $tgt"
    run_header "bloodhound" "${CMD[*]}"
    "${CMD[@]}" 2>&1
  fi

  if detect_evilwinrm; then
    section "evil-winrm"
    local CMD=(evil-winrm -i "$tgt" -u "$user" -p "$pass")
    log_command "evil-winrm -i $tgt -u $user"
    run_header "evil-winrm" "evil-winrm -i $tgt -u $user"
    printf '%b[!] Interactive — type exit to continue%b\n\n' "${C_YLW}" "${C_RST}"
    "${CMD[@]}" 2>&1
  fi

  if detect_impacket; then
    local script_path=""
    for _c in \
      "$SCRIPT_DIR/tools/impacket/examples/secretsdump.py" \
      "$SCRIPT_DIR/tools/impacket/build/scripts-3.13/secretsdump.py"; do
      [[ -f "$_c" ]] && { script_path="$_c"; break; }
    done
    if [[ -n "$script_path" ]]; then
      section "impacket/secretsdump"; local _tmp; _tmp=$(mktemp)
      log_command "secretsdump.py $domain/$user@$tgt"
      run_header "secretsdump" "$domain/$user@$tgt"
      "$PYTHON_CMD" "$script_path" "$domain/$user:$pass@$tgt" 2>&1 | tee "$_tmp"
      log_output "secretsdump $tgt" "$(tail -60 "$_tmp")"; rm -f "$_tmp"
    fi
  fi

  printf '\n%b[✔] ad-recon complete%b\n' "${C_BGRN}" "${C_RST}"
}

# ─── Export JSON ──────────────────────────────────────────────────────────────
export_json() {
  local export_file="$SESSION_DIR/dexter_export_$(date '+%Y%m%d_%H%M%S').json"

  _je() {  # JSON-escape a string via python, fallback to sed
    printf '%s' "$1" | "$PYTHON_CMD" -c \
      'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))' 2>/dev/null \
      || printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')"
  }

  {
    printf '{\n'
    printf '  "tool": "dexter-toolkit",\n'
    printf '  "target": %s,\n'   "$(_je "${SESSION_TARGET:-}")"
    printf '  "started": %s,\n'  "$(_je "$SESSION_START_TIME")"
    printf '  "exported": %s,\n' "$(_je "$(date '+%Y-%m-%d %H:%M:%S')")"

    # findings
    printf '  "findings": ['
    local _first=1
    for f in "${SESSION_FINDINGS[@]}"; do
      [[ $_first -eq 0 ]] && printf ','
      printf '\n    %s' "$(_je "$f")"; _first=0
    done
    printf '\n  ],\n'

    # notes
    printf '  "notes": ['
    _first=1
    for n in "${SESSION_NOTES[@]}"; do
      [[ $_first -eq 0 ]] && printf ','
      printf '\n    %s' "$(_je "$n")"; _first=0
    done
    printf '\n  ],\n'

    # commands (from session log)
    printf '  "commands": ['
    _first=1
    while IFS= read -r _cmd; do
      [[ -z "$_cmd" ]] && continue
      [[ $_first -eq 0 ]] && printf ','
      printf '\n    %s' "$(_je "$_cmd")"; _first=0
    done < <(grep '\[CMD\]' "$SESSION_FILE" 2>/dev/null | sed 's/\[.*\] \[CMD\] //')
    printf '\n  ],\n'

    # outputs
    printf '  "outputs": ['
    _first=1
    for o in "${SESSION_OUTPUTS[@]}"; do
      [[ $_first -eq 0 ]] && printf ','
      printf '\n    %s' "$(_je "$o")"; _first=0
    done
    printf '\n  ]\n}\n'
  } > "$export_file"

  printf '\n%b[+] JSON exported → %s%b\n' "${C_BGRN}" "$export_file" "${C_RST}"
  if command_exists wl-copy; then
    wl-copy < "$export_file" && printf '%b[+] Copied to clipboard (wl-copy)%b\n' "${C_BGRN}" "${C_RST}"
  elif command_exists xclip; then
    xclip -selection clipboard < "$export_file" && printf '%b[+] Copied to clipboard (xclip)%b\n' "${C_BGRN}" "${C_RST}"
  fi
  echo ""
}

# ─── Read with readline ───────────────────────────────────────────────────────
read_with_history() {
  local prompt="$1" input=""
  if [[ -t 0 ]]; then read -e -r -p "$prompt" input || return 1
  else printf '%s' "$prompt" >&2; read -r input || return 1; fi
  printf '%s' "$input"
}

# ─── Main REPL ────────────────────────────────────────────────────────────────
main() {
  init_session
  setup_venv 2>/dev/null || true

  set -o history
  export HISTFILE HISTSIZE HISTFILESIZE
  bind '"\e[A":history-search-backward' 2>/dev/null || true
  bind '"\e[B":history-search-forward'  2>/dev/null || true
  bind '"\e[C":forward-char'            2>/dev/null || true
  bind '"\e[D":backward-char'           2>/dev/null || true

  clear
  show_banner
  show_tools_menu

  printf '\n%b  Session started: %s%b\n' "${C_DIM}" "$SESSION_START_TIME" "${C_RST}"
  printf '%b  Log: %s%b\n\n' "${C_DIM}" "$SESSION_FILE" "${C_RST}"

  while true; do
    local target_prompt="" input=""
    [[ -n "$SESSION_TARGET" ]] && target_prompt="${SESSION_TARGET}"

    printf '%b┌─[%bdx%b]%s%b\n└─%b❯%b ' \
      "${C_DIM}${C_GRN}" "${C_BGRN}" "${C_DIM}${C_GRN}" \
      "${target_prompt:+─[${C_BCYN}${target_prompt}${C_DIM}${C_GRN}]}" \
      "${C_RST}" "${C_BGRN}" "${C_RST}"

    if ! read -r input; then
      echo ""
      break
    fi

    [[ -z "$input" ]] && continue
    log_session "[INPUT] $input"
    save_history

    # Slash commands
    if [[ "$input" == /* ]]; then
      local cmd="${input%% *}"
      local args="${input#* }"
      [[ "$cmd" == "$input" ]] && args=""

      case "$cmd" in
        /target)
          if [[ -z "$args" ]]; then
            printf '  Target: %b%s%b\n'    "${C_BCYN}" "${SESSION_TARGET:-<not set>}" "${C_RST}"
            printf '  Session dir: %b%s%b\n' "${C_DIM}"  "$SESSION_DIR" "${C_RST}"
          else
            local _raw="${args// /}"
            if ! validate_target "$_raw"; then
              printf '%b[!] Warning: "%s" may not be a valid IP, domain, or URL.%b\n' "${C_YLW}" "$_raw" "${C_RST}"
              read -r -p "  Set anyway? (y/N): " _cont
              [[ ! "$_cont" =~ ^[Yy]$ ]] && continue
            fi
            SESSION_TARGET="$_raw"
            # Isolate results in target-specific directory
            local _tdir; _tdir="$(sanitize_for_dir "$_raw")"
            local _new_dir="$SCRIPT_DIR/results/$_tdir"
            mkdir -p "$_new_dir"
            local _new_file="$_new_dir/session_$(date '+%Y%m%d_%H%M%S').log"
            [[ -f "$SESSION_FILE" ]] && cp "$SESSION_FILE" "$_new_file"
            SESSION_FILE="$_new_file"
            SESSION_DIR="$_new_dir"
            log_session "[TARGET] $_raw"
            printf '  %b[✔] Target set: %s%b\n'     "${C_BGRN}" "$_raw"      "${C_RST}"
            printf '  %b[✔] Session dir: %s%b\n'    "${C_DIM}"  "$SESSION_DIR" "${C_RST}"
          fi ;;

        /note)
          if [[ -z "$args" ]]; then
            printf '  Usage: /note <text>\n'
          else
            log_note "$args"
            printf '  %b[✔] Note saved%b\n' "${C_BGRN}" "${C_RST}"
          fi ;;

        /find)
          if [[ -z "$args" ]]; then
            printf '  Usage: /find <text>\n'
          else
            log_finding "$args"
            printf '  %b[✔] Finding recorded%b\n' "${C_BGRN}" "${C_RST}"
          fi ;;

        /context)     show_context ;;
        /export)      export_session ;;
        /export-json) export_json ;;

        /recon-auto)
          run_recon_auto "$args" ;;

        /history)
          printf '\n%b  Command history (last 20):%b\n' "${C_BCYN}" "${C_RST}"
          local total="${#SESSION_COMMANDS[@]}"
          local start=$(( total > 20 ? total - 20 : 0 ))
          for ((i=start; i<total; i++)); do
            printf '  %b%d.%b %s\n' "${C_DIM}" "$((i+1))" "${C_RST}" "${SESSION_COMMANDS[$i]}"
          done
          echo "" ;;

        /clear)
          clear
          show_banner
          show_tools_menu ;;

        /save)
          save_history
          printf '  %b[✔] Session saved → %s%b\n' "${C_BGRN}" "$SESSION_FILE" "${C_RST}" ;;

        /help)     show_help ;;

        /exit|/quit|/q)
          printf '\n%b  Saving session...%b\n' "${C_DIM}" "${C_RST}"
          show_context >> "$SESSION_FILE"
          save_history
          printf '%b  Log → %s%b\n' "${C_BGRN}" "$SESSION_FILE" "${C_RST}"
          printf '%b  Goodbye.%b\n\n' "${C_BCYN}" "${C_RST}"
          exit 0 ;;

        *)
          printf '%b[!] Unknown command: %s%b\n' "${C_YLW}" "$cmd" "${C_RST}"
          printf '  Type %b/help%b for available commands\n' "${C_BOLD}" "${C_RST}" ;;
      esac

    else
      # Tool commands
      local tool="${input%% *}"

      case "$tool" in
        nmap)          run_nmap ;;
        crtsh|crt.sh)  run_crtsh ;;
        subfinder)     run_subfinder ;;
        dirsearch)     run_dirsearch ;;
        ffuf)          run_ffuf ;;
        xsstrike)      run_xsstrike ;;
        httpx)         run_httpx ;;
        rustscan)      run_rustscan ;;
        sqlmap)        run_sqlmap ;;
        bloodhound)    run_bloodhound ;;
        evil-winrm|evilwinrm) run_evilwinrm ;;
        impacket)      run_impacket ;;
        metasploit|msfconsole) run_metasploit ;;
        ligolo)        run_ligolo ;;
        sshuttle)      run_sshuttle ;;
        chisel)        run_chisel ;;
        semgrep)       run_semgrep ;;
        wafw00f)       run_wafw00f ;;
        wpscan)        run_wpscan ;;
        cewl)          run_cewl ;;
        pspy)          run_pspy ;;
        git-dumper|gitdumper) run_gitdumper ;;

        template|templates) run_template ;;

        clear)
          clear; show_banner; show_tools_menu ;;

        *)
          if command_exists "$tool"; then
            log_command "$input"
            eval "$input" 2>&1
          else
            printf '%b[!] Unknown: %s%b — type %b/help%b\n' \
              "${C_YLW}" "$tool" "${C_RST}" "${C_BOLD}" "${C_RST}"
          fi ;;
      esac
    fi

    save_history
  done

  save_history
  show_context >> "$SESSION_FILE"
}

trap 'echo ""; printf "%b  Saving session...%b\n" "${C_DIM}" "${C_RST}"; save_history; show_context >> "$SESSION_FILE"; exit 0' INT TERM

main "$@"
