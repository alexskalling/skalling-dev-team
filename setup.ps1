# setup.ps1 — Wrapper PowerShell para setup per-project en Windows.
#
# Igual a install-global.ps1 pero llama a setup.sh en lugar de install-global.sh.
# Delega a bash (Git Bash, WSL, o Cygwin).

[CmdletBinding()]
param(
    [string]$Target = "",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$SkipBackup,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @"
setup.ps1 — Instala Skalling en un proyecto específico (Windows)

Uso:
    .\setup.ps1                                # instalar en directorio actual
    .\setup.ps1 -Target C:\path\to\project     # instalar en proyecto específico
    .\setup.ps1 -DryRun                        # ver qué haría
    .\setup.ps1 -Force                         # sobrescribir sin preguntar
    .\setup.ps1 -SkipBackup                    # no crear backup

Requisitos:
    - bash disponible (Git Bash, WSL2, o Cygwin)
    - Haber corrido install-global.ps1 primero
"@
    exit 0
}

if ($Help) { Show-Help }

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS (compartidos con install-global.ps1)
# ──────────────────────────────────────────────────────────────────────────────

function Find-Bash {
    $bashPaths = @(
        "bash",
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "C:\Windows\System32\bash.exe",
        "C:\Program Files\WSL\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe"
    )
    foreach ($path in $bashPaths) {
        try {
            if ($path -eq "bash") {
                return (Get-Command bash -ErrorAction Stop).Source
            }
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                return $path
            }
        } catch {}
    }
    return $null
}

function Find-SkallingDir {
    $candidates = @(
        "$PSScriptRoot",
        "$env:USERPROFILE\skalling-dev-team",
        "$env:USERPROFILE\Proyectos\skalling-dev-team"
    )
    foreach ($dir in $candidates) {
        if (Test-Path "$dir\setup.sh" -ErrorAction SilentlyContinue) {
            return $dir
        }
    }
    return $null
}

function Convert-WindowsPathToBash {
    param([string]$WindowsPath)
    if ($script:BashPath -match "System32\\bash.exe|Program Files\\WSL") {
        $drive = $WindowsPath.Substring(0, 1).ToLower()
        $rest = $WindowsPath.Substring(2) -replace "\\", "/"
        return "/mnt/$drive/$rest"
    } else {
        $drive = $WindowsPath.Substring(0, 1).ToLower()
        $rest = $WindowsPath.Substring(2) -replace "\\", "/"
        return "/$drive/$rest"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Skalling — Setup per-project (Windows)" -ForegroundColor Cyan
Write-Host ""

$script:BashPath = Find-Bash
$skallingDir = Find-SkallingDir

if (-not $script:BashPath) {
    Write-Host "  bash no encontrado." -ForegroundColor Red
    Write-Host "  Instalá Git Bash o WSL2. Ver install-global.ps1 para detalles." -ForegroundColor Yellow
    exit 1
}

if (-not $skallingDir) {
    Write-Host "  skalling-dev-team no encontrado." -ForegroundColor Red
    exit 1
}

Write-Host "  bash: $script:BashPath" -ForegroundColor Green
Write-Host "  skalling-dev-team: $skallingDir" -ForegroundColor Green

if ($Target) {
    Write-Host "  Target: $Target" -ForegroundColor Green
    $bashTarget = Convert-WindowsPathToBash $Target
} else {
    $bashTarget = ""
}

$bashSkallingDir = Convert-WindowsPathToBash $skallingDir
$bashArgs = @("$bashSkallingDir/setup.sh")
if ($bashTarget) { $bashArgs += "--target"; $bashArgs += $bashTarget }
if ($DryRun) { $bashArgs += "--dry-run" }
if ($Force) { $bashArgs += "--force" }
if ($SkipBackup) { $bashArgs += "--skip-backup" }

Write-Host ""
Write-Host "  Ejecutando: bash $($bashArgs -join ' ')" -ForegroundColor Cyan
Write-Host ""

try {
    & $script:BashPath @bashArgs
    exit $LASTEXITCODE
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}
