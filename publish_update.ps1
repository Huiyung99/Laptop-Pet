# Publishes a new version: signs pet.ps1, writes update\, rebuilds the exe, pushes to GitHub.
#   1. In pet.ps1 raise  $AppVersion = N
#   2. powershell -ExecutionPolicy Bypass -File publish_update.ps1          (add -NoPush to skip git)
# The private signing key stays at %APPDATA%\LaptopPet-signing\update_key.xml. Never put it in the repo.
param([switch]$NoPush)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$keyFile = Join-Path $env:APPDATA 'LaptopPet-signing\update_key.xml'
if (-not (Test-Path $keyFile)) { throw "Signing key not found: $keyFile" }

$src = Join-Path $here 'pet.ps1'
$bytes = [IO.File]::ReadAllBytes($src)
$text = [Text.Encoding]::UTF8.GetString($bytes)
if ($text -notmatch '(?m)^\$AppVersion = (\d+)') { throw 'No $AppVersion line in pet.ps1' }
$ver = [int]$Matches[1]

$updDir = Join-Path $here 'update'
$manifestFile = Join-Path $updDir 'latest.json'
if (Test-Path $manifestFile) {
    $old = [int](Get-Content -Raw $manifestFile | ConvertFrom-Json).version
    if ($ver -le $old) { throw "Version $ver is not newer than the published version $old. Raise `$AppVersion in pet.ps1 first." }
}

$sha = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
$rsa.FromXmlString([IO.File]::ReadAllText($keyFile))
$sig = [Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes("$ver`n$sha"), 'SHA256'))

New-Item -ItemType Directory -Force $updDir | Out-Null
[IO.File]::WriteAllBytes((Join-Path $updDir 'pet.ps1'), $bytes)
$manifest = [ordered]@{ version = $ver; sha256 = $sha; sig = $sig } | ConvertTo-Json
[IO.File]::WriteAllText($manifestFile, $manifest, (New-Object Text.UTF8Encoding($false)))
"Signed version $ver ($sha)"

& (Join-Path $here 'build_exe.ps1')

if (-not $NoPush) {
    git -C $here add -A
    git -C $here commit -m "Version $ver"
    git -C $here push
}
