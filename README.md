# Dexter Toolkit

```
  ██████╗ ███████╗██╗  ██╗████████╗███████╗██████╗
  ██╔══██╗██╔════╝╚██╗██╔╝╚══██╔══╝██╔════╝██╔══██╗
  ██║  ██║█████╗   ╚███╔╝    ██║   █████╗  ██████╔╝
  ██║  ██║██╔══╝   ██╔██╗    ██║   ██╔══╝  ██╔══██╗
  ██████╔╝███████╗██╔╝ ██╗   ██║   ███████╗██║  ██║
  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
         ·  TONIGHT IS THE NIGHT  ·
```

**Dexter** is an interactive penetration testing framework built as a single Bash script. It provides a unified shell interface for orchestrating security tools, managing session state, logging findings, and exporting structured reports — all from one place.

Designed for authorized engagements, CTF competitions, and security research.

---

## Features

### Interactive Shell
- Persistent session state: target, notes, findings, command history
- Color-coded terminal UI with boxed section headers and run banners
- Input validation for IPs, domains, and URLs
- Built-in command history with up-arrow recall

### Tool Detection
Dexter automatically detects which tools are installed and shows their availability at startup:

| Category | Tools |
|---|---|
| Recon | nmap, subfinder, rustscan, httpx, ffuf, dirsearch, crt.sh |
| Vulnerability Assessment | sqlmap, XSStrike, wafw00f, semgrep |
| Active Directory / Network | bloodhound-python, evil-winrm, impacket |
| Exploitation | metasploit |
| Pivoting | chisel, sshuttle, ligolo |
| Post-Exploitation | pspy64, git-dumper |

### Session Management
- Every command and output is logged to a timestamped session file
- `/export` — saves the full session as a plain-text file (paste directly into an LLM for analysis)
- `/export-json` — saves the session as structured JSON for scripting/reporting

### Automation
- `/recon-auto [target]` — chains subfinder → httpx → nmap → dirsearch automatically
- `template` — runs predefined attack templates:
  - `web-basic` — wafw00f → nmap → httpx → dirsearch
  - `ctf-web` — crt.sh → subfinder → httpx → ffuf
  - `ad-recon` — bloodhound → evil-winrm → secretsdump (impacket)

### Python venv Integration
Dexter automatically creates and activates a `.venv` inside its directory so Python-based tools (sqlmap, XSStrike, bloodhound-python, wafw00f, semgrep, git-dumper) run in isolation without polluting your system Python.

---

## Requirements

- **OS:** Linux (tested on Arch, Kali, Ubuntu)
- **Shell:** Bash 4+
- **Core deps:** `git`, `curl`, `jq`, `python3`
- **Optional:** `go` (for subfinder, ffuf, httpx), `nmap`, `rustscan`, `metasploit`

---

## Installation

### Quick Install (recommended)

```bash
git clone https://github.com/YOUR_USERNAME/Dexter_Toolkit.git
cd Dexter_Toolkit
chmod +x build.sh
./build.sh
```

`build.sh` installs the `dexter` command to `~/.local/bin/`. If `shc` is available it compiles to a true binary; otherwise it creates a symlink.

### Make it available system-wide

Add `~/.local/bin` to your PATH by adding this line to your `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload your shell:

```bash
source ~/.zshrc   # or source ~/.bashrc
```

Now you can run Dexter from any terminal:

```bash
dexter
```

### Manual (no build step)

```bash
git clone https://github.com/YOUR_USERNAME/Dexter_Toolkit.git
cd Dexter_Toolkit
chmod +x dexter.sh
./dexter.sh
```

---

## Usage

```
dexter
```

At the prompt, use slash commands to control the session:

```
/target <domain|IP|URL>   — set the current engagement target
/target                   — show current target

/note <text>              — add a session note
/find <text>              — record a finding

/context                  — print full session state (target, notes, findings)
/history                  — show command history

/recon-auto [target]      — auto-chain: subfinder → httpx → nmap → dirsearch
template                  — select and run an attack template

/export                   — export session to TXT (ideal for LLM context)
/export-json              — export session as structured JSON

/help                     — show all available commands
/exit                     — exit and save session
```

### Example Workflow

```bash
dexter
# At the prompt:
/target example.com
/recon-auto
/find Open port 8080 — Tomcat admin exposed
/note Tried default creds, no luck
/export
```

---

## Installing Tools

Dexter works with whatever tools you already have. Install the ones you need:

```bash
# Kali / Debian
sudo apt install nmap ffuf httpx-toolkit rustscan sqlmap bloodhound python3-impacket

# Go tools
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/ffuf/ffuf/v2@latest

# Python tools (inside venv — Dexter handles this automatically)
pip install sqlmap xsstrike wafw00f semgrep bloodhound git-dumper

# Arch Linux
sudo pacman -S nmap python
yay -S rustscan sqlmap
```

Tools can also be placed inside a `tools/` directory alongside `dexter.sh` and symlinked into `bin/` — Dexter will detect them automatically.

---

## Session Files

By default, session logs are written to a `results/` directory next to the script. These files are **excluded from version control** via `.gitignore` and should be treated as sensitive — they may contain target names, scan outputs, and findings.

---

## License

MIT — free to use, modify, and distribute. See [LICENSE](LICENSE) for details.

---

> **Disclaimer:** This tool is intended for authorized security testing only. Always obtain proper written permission before testing any system you do not own. The authors assume no liability for misuse.
