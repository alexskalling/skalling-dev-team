# setup-team-doctor.ps1 — Wrapper PowerShell para health check en Windows.

[CmdletBinding()]
param(
    [string]$SkallingDir = "",
    [string]$Project = "",
    [ValidateSet("Auto", "GitBash", "WSL")]
    [string]$Runtime = "Auto",
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

function Find-GitBash {
    $paths = @("C:\Program Files\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
    foreach ($p in $paths) {
        try {
            if (Test-Path $p -ErrorAction SilentlyContinue) { return $p }
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
        if (-not (Test-Path "$resolved\setup-team-doctor.sh")) { throw "No se encontró setup-team-doctor.sh en $resolved" }
        return $resolved.Path
    }
    $candidates = @("$PSScriptRoot", "$env:USERPROFILE\skalling-dev-team")
    foreach ($d in $candidates) {
        if (Test-Path "$d\setup-team-doctor.sh") { return $d }
    }
    return $null
}

function Convert-WinToBashPath {
    param([string]$Path)
    if ($script:RuntimeKind -eq "WSL") {
        $converted = & $script:RuntimeCommand wslpath -a $Path
    } else {
        $converted = & $script:RuntimeCommand -c 'cygpath -u -- "$1"' _ $Path
    }
    if ($LASTEXITCODE -ne 0 -or -not $converted) { throw "No se pudo convertir la ruta: $Path" }
    return ($converted | Select-Object -First 1).Trim()
}

Write-Host ""
Write-Host "  Skalling Doctor — Windows" -ForegroundColor Cyan
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
    exit 1
}
if (-not $resolvedSkallingDir) {
    Write-Host "  skalling-dev-team no encontrado." -ForegroundColor Red
    exit 1
}

Write-Host "  Runtime: $script:RuntimeKind ($script:RuntimeCommand)" -ForegroundColor Green
Write-Host "  skalling-dev-team: $resolvedSkallingDir" -ForegroundColor Green

$bashSkallingDir = Convert-WinToBashPath $resolvedSkallingDir
$bashArgs = @("$bashSkallingDir/setup-team-doctor.sh")
if ($Project) { $bashArgs += "--project"; $bashArgs += (Convert-WinToBashPath (Resolve-Path $Project).Path) }
if ($GlobalOnly) { $bashArgs += "--global-only" }
if ($Strict) { $bashArgs += "--strict" }

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
