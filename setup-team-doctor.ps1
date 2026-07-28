# setup-team-doctor.ps1 — Wrapper PowerShell para health check en Windows.

[CmdletBinding()]
param(
    [string]$Project = "",
    [switch]$GlobalOnly,
    [switch]$Strict,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @"
setup-team-doctor.ps1 — Health check de Skalling (Windows)

Uso:
    .\setup-team-doctor.ps1                          # chequea global + cwd
    .\setup-team-doctor.ps1 -Project C:\path\proj   # proyecto específico
    .\setup-team-doctor.ps1 -GlobalOnly             # solo global
    .\setup-team-doctor.ps1 -Strict                 # warnings como errors
"@
    exit 0
}

if ($Help) { Show-Help }

function Find-Bash {
    $paths = @("bash", "C:\Program Files\Git\bin\bash.exe", "C:\Windows\System32\bash.exe")
    foreach ($p in $paths) {
        try {
            if ($p -eq "bash") { return (Get-Command bash -ErrorAction Stop).Source }
            if (Test-Path $p -ErrorAction SilentlyContinue) { return $p }
        } catch {}
    }
    return $null
}

function Find-SkallingDir {
    $candidates = @("$PSScriptRoot", "$env:USERPROFILE\skalling-dev-team")
    foreach ($d in $candidates) {
        if (Test-Path "$d\setup-team-doctor.sh") { return $d }
    }
    return $null
}

function Convert-WinToBashPath {
    param([string]$Path)
    $drive = $Path.Substring(0, 1).ToLower()
    $rest = $Path.Substring(2) -replace "\\", "/"
    if ($script:BashPath -match "System32\\bash.exe|Program Files\\WSL") {
        return "/mnt/$drive/$rest"
    }
    return "/$drive/$rest"
}

Write-Host ""
Write-Host "  Skalling Doctor — Windows" -ForegroundColor Cyan
Write-Host ""

$script:BashPath = Find-Bash
$skallingDir = Find-SkallingDir

if (-not $script:BashPath) {
    Write-Host "  bash no encontrado." -ForegroundColor Red
    exit 1
}
if (-not $skallingDir) {
    Write-Host "  skalling-dev-team no encontrado." -ForegroundColor Red
    exit 1
}

Write-Host "  bash: $script:BashPath" -ForegroundColor Green
Write-Host "  skalling-dev-team: $skallingDir" -ForegroundColor Green

$bashSkallingDir = Convert-WinToBashPath $skallingDir
$bashArgs = @("$bashSkallingDir/setup-team-doctor.sh")
if ($Project) { $bashArgs += "--project"; $bashArgs += (Convert-WinToBashPath $Project) }
if ($GlobalOnly) { $bashArgs += "--global-only" }
if ($Strict) { $bashArgs += "--strict" }

Write-Host ""
try {
    & $script:BashPath @bashArgs
    exit $LASTEXITCODE
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}
