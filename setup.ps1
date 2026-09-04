# setup.ps1 — Wrapper PowerShell para setup per-project en Windows.
#
# Igual a install-global.ps1 pero llama a setup.sh en lugar de install-global.sh.
# Delega a bash (Git Bash, WSL, o Cygwin).

[CmdletBinding()]
param(
    [string]$SkallingDir = "",
    [string]$Target = "",
    [ValidateSet("Auto", "GitBash", "WSL")]
    [string]$Runtime = "Auto",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$SkipBackup,
    [switch]$Uninstall,
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
    .\setup.ps1 -Uninstall                     # desinstalar del proyecto
    .\setup.ps1 -Runtime WSL                   # operar dentro de WSL

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

function Find-GitBash {
    $bashPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($path in $bashPaths) {
        try {
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                return $path
            }
        } catch {}
    }
    return $null
}

function Find-Wsl {
    try { return (Get-Command wsl.exe -ErrorAction Stop).Source } catch { return $null }
}

function Resolve-SkallingDir {
    if ($SkallingDir) {
        $resolved = Resolve-Path $SkallingDir -ErrorAction Stop
        if (-not (Test-Path "$resolved\setup.sh")) { throw "No se encontró setup.sh en $resolved" }
        return $resolved.Path
    }
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

function Convert-WindowsPathToRuntime {
    param([string]$WindowsPath)
    if ($script:RuntimeKind -eq "WSL") {
        $converted = & $script:RuntimeCommand wslpath -a $WindowsPath
    } else {
        $converted = & $script:RuntimeCommand -c 'cygpath -u -- "$1"' _ $WindowsPath
    }
    if ($LASTEXITCODE -ne 0 -or -not $converted) { throw "No se pudo convertir la ruta: $WindowsPath" }
    return ($converted | Select-Object -First 1).Trim()
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Skalling — Setup per-project (Windows)" -ForegroundColor Cyan
Write-Host ""

$gitBash = Find-GitBash
$wsl = Find-Wsl
if ($Runtime -eq "GitBash" -or ($Runtime -eq "Auto" -and $gitBash)) {
    $script:RuntimeKind = "GitBash"; $script:RuntimeCommand = $gitBash
} elseif ($Runtime -eq "WSL" -or ($Runtime -eq "Auto" -and $wsl)) {
    $script:RuntimeKind = "WSL"; $script:RuntimeCommand = $wsl
}
$resolvedSkallingDir = Resolve-SkallingDir

if (-not $script:RuntimeCommand) {
    Write-Host "  Git Bash o WSL2 no encontrado." -ForegroundColor Red
    Write-Host "  Instalá Git Bash o WSL2. Ver install-global.ps1 para detalles." -ForegroundColor Yellow
    exit 1
}

if (-not $resolvedSkallingDir) {
    Write-Host "  skalling-dev-team no encontrado." -ForegroundColor Red
    exit 1
}

Write-Host "  Runtime: $script:RuntimeKind ($script:RuntimeCommand)" -ForegroundColor Green
Write-Host "  skalling-dev-team: $resolvedSkallingDir" -ForegroundColor Green
if ($script:RuntimeKind -eq "WSL") {
    Write-Host "  Se modificará el proyecto desde WSL; usá OpenCode dentro del mismo WSL." -ForegroundColor Yellow
}

if ($Target) {
    Write-Host "  Target: $Target" -ForegroundColor Green
    $bashTarget = Convert-WindowsPathToRuntime (Resolve-Path $Target).Path
} else {
    $bashTarget = ""
}

$bashSkallingDir = Convert-WindowsPathToRuntime $resolvedSkallingDir
$bashArgs = @("$bashSkallingDir/setup.sh")
if ($bashTarget) { $bashArgs += "--target"; $bashArgs += $bashTarget }
if ($DryRun) { $bashArgs += "--dry-run" }
if ($Force) { $bashArgs += "--force" }
if ($SkipBackup) { $bashArgs += "--skip-backup" }
if ($Uninstall) { $bashArgs += "--uninstall" }

Write-Host ""
Write-Host "  Ejecutando: bash $($bashArgs -join ' ')" -ForegroundColor Cyan
Write-Host ""

try {
    if ($script:RuntimeKind -eq "WSL") {
        & $script:RuntimeCommand bash @bashArgs
    } else {
        & $script:RuntimeCommand @bashArgs
    }
    exit $LASTEXITCODE
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}
