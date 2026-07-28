# bootstrap-context.ps1 — Wrapper PowerShell para /skalling-init en Windows.
#
# Delega a bootstrap-context.sh vía bash.

[CmdletBinding()]
param(
    [string]$Target = "",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$OnlyDetection,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @"
bootstrap-context.ps1 — Inicializa bundle OKF en un proyecto (Windows)

Uso:
    .\bootstrap-context.ps1                       # en directorio actual
    .\bootstrap-context.ps1 -Target C:\path\proj   # en proyecto específico
    .\bootstrap-context.ps1 -DryRun                # ver qué haría
    .\bootstrap-context.ps1 -Force                 # regenerar
    .\bootstrap-context.ps1 -OnlyDetection         # solo detectar stack
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
        if (Test-Path "$d\bootstrap-context.sh") { return $d }
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
Write-Host "  Skalling — Bootstrap (Windows)" -ForegroundColor Cyan
Write-Host ""

$script:BashPath = Find-Bash
$skallingDir = Find-SkallingDir

if (-not $script:BashPath) {
    Write-Host "  bash no encontrado. Instalá Git Bash o WSL2." -ForegroundColor Red
    exit 1
}

if (-not $skallingDir) {
    Write-Host "  skalling-dev-team no encontrado." -ForegroundColor Red
    exit 1
}

Write-Host "  bash: $script:BashPath" -ForegroundColor Green
Write-Host "  skalling-dev-team: $skallingDir" -ForegroundColor Green

$bashSkallingDir = Convert-WinToBashPath $skallingDir
$bashArgs = @("$bashSkallingDir/bootstrap-context.sh")
if ($Target) { $bashArgs += "--target"; $bashArgs += (Convert-WinToBashPath $Target) }
if ($DryRun) { $bashArgs += "--dry-run" }
if ($Force) { $bashArgs += "--force" }
if ($OnlyDetection) { $bashArgs += "--only-detection" }

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
