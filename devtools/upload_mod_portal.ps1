param(
    [string]$ZipPath,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonScript = Join-Path $PSScriptRoot "upload_mod_portal.py"
$argsList = @($pythonScript)

if (-not $env:FACTORIO_MOD_PORTAL_API_KEY) {
    $env:FACTORIO_MOD_PORTAL_API_KEY =
        [Environment]::GetEnvironmentVariable("FACTORIO_MOD_PORTAL_API_KEY", "User")
}

if ($ZipPath) {
    $argsList += "--zip-path"
    $argsList += $ZipPath
}

if ($SkipBuild) {
    $argsList += "--skip-build"
}

& python $argsList

if ($LASTEXITCODE -ne 0) {
    throw "upload_mod_portal.py failed."
}
