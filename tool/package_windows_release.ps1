# Build the Windows release bundle and package it as a zip archive.
#
# The bundle contains the Flutter runtime, the Node.js engine, its npm
# dependencies, and abyss-dl.jar, so running the extracted app requires no
# engine-path configuration. Node.js, Java 21+ (Abyss), mpv, and a Chromium
# browser still need to be installed on the machine.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Version = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$FlutterArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
$Bundle = Join-Path $Root "build\windows\$FlutterArch\runner\Release"
$Dist = Join-Path $Root "dist"
$Name = "anime-tui-native-$Version-windows-$FlutterArch"

if (-not (Test-Path "node_modules")) {
  Write-Host "Installing engine dependencies..."
  npm install --omit=dev
  if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
}

Write-Host "Building Windows release..."
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

$required = @(
  (Join-Path $Bundle "anime_tui_native.exe"),
  (Join-Path $Bundle "engine\anime.js"),
  (Join-Path $Bundle "engine\abyss-dl.jar"),
  (Join-Path $Bundle "engine\lib\playback.js"),
  (Join-Path $Bundle "engine\node_modules")
)
foreach ($path in $required) {
  if (-not (Test-Path $path)) {
    throw "Release bundle is incomplete: missing $path"
  }
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$Staging = Join-Path $Dist $Name
$Archive = Join-Path $Dist "$Name.zip"
if (Test-Path $Staging) { Remove-Item -Recurse -Force $Staging }
if (Test-Path $Archive) { Remove-Item -Force $Archive }

New-Item -ItemType Directory -Force -Path $Staging | Out-Null
Copy-Item -Recurse -Force (Join-Path $Bundle "*") $Staging
Copy-Item -Force (Join-Path $Root "README.md") (Join-Path $Staging "README.md")

Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $Archive -CompressionLevel Optimal

Write-Host ""
Write-Host "Packaged: $Archive"
Write-Host "Run it by extracting the zip and starting anime_tui_native.exe."
