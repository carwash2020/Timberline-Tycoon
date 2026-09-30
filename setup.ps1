# One-time setup on a new Windows computer. Double-click setup.cmd, or run:
#   powershell -ExecutionPolicy Bypass -File setup.ps1
# 1. Installs Rokit (the toolchain manager) if it's missing.
# 2. Installs the exact tool versions pinned in rokit.toml
#    (Rojo, StyLua, Selene, luau-lsp).
# 3. Installs the matching Rojo plugin into Roblox Studio.
# Safe to re-run: anything already installed is left alone.
# Native tools report failure via $LASTEXITCODE (checked below); "Continue" keeps
# their normal stderr progress output from being treated as a script error.
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$rokitBin = Join-Path $env:USERPROFILE ".rokit\bin"

if (-not (Get-Command rokit -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $rokitBin "rokit.exe"))) {
	Write-Host "==> Installing Rokit"
	Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 -ErrorAction Stop | Invoke-Expression
}
# The installer adds Rokit to PATH for *new* windows; make it work in this one too.
$env:PATH = "$rokitBin;$env:PATH"

Write-Host "==> Trusting the tools listed in rokit.toml"
foreach ($line in Get-Content rokit.toml) {
	if ($line -match '^\s*[A-Za-z0-9_-]+\s*=\s*"([^@"]+)@') {
		rokit trust $Matches[1]
		if ($LASTEXITCODE -ne 0) { throw "rokit trust $($Matches[1]) failed" }
	}
}

Write-Host "==> Installing tools"
rokit install
if ($LASTEXITCODE -ne 0) {
	Write-Host ""
	Write-Host "Couldn't download the tools. Check the internet connection and run setup again."
	Write-Host "On a shared network GitHub may be rate-limiting you: run 'rokit authenticate github' first."
	exit 1
}

Write-Host "==> Installing the Rojo plugin into Roblox Studio"
rojo plugin install
if ($LASTEXITCODE -ne 0) {
	Write-Host "Couldn't install the Studio plugin automatically. Install Roblox Studio (and open it"
	Write-Host "once), then run setup again, or add 'Rojo' from Studio's Plugins marketplace."
}

Write-Host ""
Write-Host "All set. Open a new terminal in this folder, then:"
Write-Host "  rojo serve      (leave it running)"
Write-Host "  In Roblox Studio: Plugins -> Rojo -> Connect, then press Play."
