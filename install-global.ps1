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

function Find-Bash {
    # Buscar bash en orden de preferencia
    $bashPaths = @(
        "bash",
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "C:\Windows\System32\bash.exe",        # WSL
        "C:\Program Files\WSL\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )

    foreach ($path in $bashPaths) {
        try {
            if ($path -eq "bash") {
                $bashCmd = Get-Command bash -ErrorAction Stop
                return $bashCmd.Source
            }
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                return $path
            }
        } catch {}
    }
    return $null
}

function Find-Wsl {
    try {
        $wsl = Get-Command wsl -ErrorAction Stop
        return $wsl.Source
    } catch {
        return $null
    }
}

function Find-SkallingDir {
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

function Convert-WindowsPathToBash {
    param([string]$WindowsPath)
    # C:\Users\foo\bar -> /c/Users/foo/bar (Git Bash) o /mnt/c/Users/foo/bar (WSL)
    # Detectar qué tipo de bash tenemos
    if ($script:BashPath -match "System32\\bash.exe|Program Files\\WSL") {
        # WSL: /mnt/c/Users/...
        $drive = $WindowsPath.Substring(0, 1).ToLower()
        $rest = $WindowsPath.Substring(2) -replace "\\", "/"
        return "/mnt/$drive/$rest"
    } else {
        # Git Bash: /c/Users/...
        $drive = $WindowsPath.Substring(0, 1).ToLower()
        $rest = $WindowsPath.Substring(2) -replace "\\", "/"
        return "/$drive/$rest"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Skalling — Installer para Windows" -ForegroundColor Cyan
Write-Host ""

# Encontrar bash
$script:BashPath = Find-Bash
$skallingDir = Find-SkallingDir

if (-not $script:BashPath) {
    Write-Host "  bash no encontrado." -ForegroundColor Red
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

Write-Host "  bash: $script:BashPath" -ForegroundColor Green

# Encontrar skalling-dev-team
if (-not $skallingDir) {
    Write-Host "  skalling-dev-team no encontrado en ubicaciones comunes." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Cloná el repo primero:" -ForegroundColor Yellow
    Write-Host "    git clone https://github.com/tu-usuario/skalling-dev-team.git ~/skalling-dev-team" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  O pasá el path:" -ForegroundColor Yellow
    Write-Host "    .\install-global.ps1 -SkallingDir C:\path\to\skalling-dev-team" -ForegroundColor Cyan
    exit 1
}

Write-Host "  skalling-dev-team: $skallingDir" -ForegroundColor Green

# Convertir path a formato bash
$bashSkallingDir = Convert-WindowsPathToBash $skallingDir

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
    & $script:BashPath @bashArgs
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
