# install-global.ps1 — Wrapper PowerShell para Windows.
#
# Detecta si hay bash disponible (Git Bash, WSL, o Cygwin) y delega.
# Si no hay bash, falla con instrucciones claras para instalar WSL2 o Git Bash.
#
# Uso (PowerShell):
#   .\install-global.ps1                    # install normal
#   .\install-global.ps1 -DryRun           # ver qué haría
#   .\install-global.ps1 -Force            # sobrescribir sin preguntar
#   .\install-global.ps1 -Uninstall        # desinstalar
#
# Requisitos:
#   - Windows 10+ con bash disponible (Git Bash, WSL, o Cygwin).
#   - Si no hay bash: instalar WSL2 (`wsl --install` en PowerShell admin)
#     o Git Bash desde https://git-scm.com/download/win

[CmdletBinding()]
param(
    [string]$SkallingDir = "",
    [ValidateSet("Auto", "GitBash", "WSL")]
    [string]$Runtime = "Auto",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────

function Show-Help {
    @"
install-global.ps1 — Instala Skalling en Windows

Uso:
    .\install-global.ps1                  # install normal
    .\install-global.ps1 -DryRun          # ver qué haría
    .\install-global.ps1 -Force           # sobrescribir sin preguntar
    .\install-global.ps1 -Uninstall       # desinstalar
    .\install-global.ps1 -SkallingDir C:\ruta\skalling-dev-team
    .\install-global.ps1 -Runtime WSL     # instala dentro del entorno WSL

Requisitos:
    - Windows 10+ (64-bit)
    - bash disponible (Git Bash, WSL2, o Cygwin)

Si no tenés bash, instalá WSL2:
    wsl --install          # en PowerShell como admin
    # o Git Bash desde:
    # https://git-scm.com/download/win

Después de instalar, abrí Git Bash o WSL y corré:
    bash ~/skalling-dev-team/install-global.sh
"@
    exit 0
}

if ($Help) { Show-Help }

# ──────────────────────────────────────────────────────────────────────────────
# DETECCIÓN DE BASH
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
    try {
        $wsl = Get-Command wsl.exe -ErrorAction Stop
        return $wsl.Source
    } catch {
        return $null
    }
}

function Resolve-SkallingDir {
    if ($SkallingDir) {
        $resolved = Resolve-Path $SkallingDir -ErrorAction Stop
        if (-not (Test-Path "$resolved\install-global.sh")) {
            throw "No se encontró install-global.sh en $resolved"
        }
        return $resolved.Path
    }
    # Buscar skalling-dev-team en ubicaciones comunes
    $candidates = @(
        "$PSScriptRoot",
        "$env:USERPROFILE\skalling-dev-team",
        "$env:USERPROFILE\Proyectos\skalling-dev-team",
        "$env:USERPROFILE\Documents\skalling-dev-team",
        "C:\skalling-dev-team"
    )
    foreach ($dir in $candidates) {
        if (Test-Path "$dir\install-global.sh" -ErrorAction SilentlyContinue) {
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
    if ($LASTEXITCODE -ne 0 -or -not $converted) {
        throw "No se pudo convertir la ruta para $($script:RuntimeKind): $WindowsPath"
    }
    return ($converted | Select-Object -First 1).Trim()
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Skalling — Installer para Windows" -ForegroundColor Cyan
Write-Host ""

# Elegir un runtime sin mezclar HOME de Windows y WSL silenciosamente.
$gitBash = Find-GitBash
$wsl = Find-Wsl
if ($Runtime -eq "GitBash" -or ($Runtime -eq "Auto" -and $gitBash)) {
    $script:RuntimeKind = "GitBash"
    $script:RuntimeCommand = $gitBash
} elseif ($Runtime -eq "WSL" -or ($Runtime -eq "Auto" -and $wsl)) {
    $script:RuntimeKind = "WSL"
    $script:RuntimeCommand = $wsl
}

if (-not $script:RuntimeCommand) {
    Write-Host "  No se encontró Git Bash ni wsl.exe." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Opciones:" -ForegroundColor Yellow
    Write-Host "    1. Instalar WSL2 (recomendado):" -ForegroundColor White
    Write-Host "       PowerShell como administrador:" -ForegroundColor Gray
    Write-Host "         wsl --install" -ForegroundColor Cyan
    Write-Host "       Luego reiniciar Windows." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    2. Instalar Git Bash:" -ForegroundColor White
    Write-Host "       https://git-scm.com/download/win" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Después instalá desde bash:" -ForegroundColor Yellow
    Write-Host "    bash ~/skalling-dev-team/install-global.sh" -ForegroundColor Cyan
    exit 1
}

Write-Host "  Runtime: $script:RuntimeKind ($script:RuntimeCommand)" -ForegroundColor Green
if ($script:RuntimeKind -eq "WSL") {
    Write-Host "  La configuración se instalará dentro de WSL; ejecutá OpenCode dentro de WSL." -ForegroundColor Yellow
}

# Encontrar skalling-dev-team
$resolvedSkallingDir = Resolve-SkallingDir
if (-not $resolvedSkallingDir) {
    Write-Host "  skalling-dev-team no encontrado en ubicaciones comunes." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Cloná el repo primero:" -ForegroundColor Yellow
    Write-Host "    git clone https://github.com/tu-usuario/skalling-dev-team.git ~/skalling-dev-team" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  O pasá el path:" -ForegroundColor Yellow
    Write-Host "    .\install-global.ps1 -SkallingDir C:\path\to\skalling-dev-team" -ForegroundColor Cyan
    exit 1
}

Write-Host "  skalling-dev-team: $resolvedSkallingDir" -ForegroundColor Green

# Convertir path a formato bash
$bashSkallingDir = Convert-WindowsPathToRuntime $resolvedSkallingDir

# Construir argumentos
$bashArgs = @("$bashSkallingDir/install-global.sh")
if ($DryRun) { $bashArgs += "--dry-run" }
if ($Force) { $bashArgs += "--force" }
if ($Uninstall) { $bashArgs += "--uninstall" }

Write-Host ""
Write-Host "  Ejecutando: bash $($bashArgs -join ' ')" -ForegroundColor Cyan
Write-Host ""

# Delegar a bash
try {
    if ($script:RuntimeKind -eq "WSL") {
        & $script:RuntimeCommand bash @bashArgs
    } else {
        & $script:RuntimeCommand @bashArgs
    }
    $exitCode = $LASTEXITCODE
    Write-Host ""
    if ($exitCode -eq 0) {
        Write-Host "  ✓ Instalación exitosa" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Instalación falló (exit $exitCode)" -ForegroundColor Red
    }
    exit $exitCode
} catch {
    Write-Host "  ✗ Error ejecutando bash: $_" -ForegroundColor Red
    exit 1
}
