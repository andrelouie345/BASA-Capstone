# tool/build_release.ps1
# Builds both BASA variants for Android and Windows into build\dist, plus two
# scan APKs (build\scan, never shipped), then proves the tutor builds carry no
# admin code (tool/admin_markers.txt).
#
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -CloudUrl <url> -CloudKey <anon key>
#   (or -LanUrl/-LanKey, or set BASA_CLOUD_URL/BASA_CLOUD_KEY/BASA_LAN_URL/BASA_LAN_KEY)
#
# The server is baked into the build: release builds have no console to set it.
# Only ever the anon key, never a service_role key.
param(
    [string]$CloudUrl = $env:BASA_CLOUD_URL,
    [string]$CloudKey = $env:BASA_CLOUD_KEY,
    [string]$LanUrl = $env:BASA_LAN_URL,
    [string]$LanKey = $env:BASA_LAN_KEY
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$hasCloud = $CloudUrl -and $CloudKey
$hasLan = $LanUrl -and $LanKey
if (-not ($hasCloud -or $hasLan)) {
    Write-Host 'No server given: pass -CloudUrl and -CloudKey (or -LanUrl and -LanKey). A release build has no console to set it later.' -ForegroundColor Red
    exit 2
}
$defines = @()
if ($CloudUrl) { $defines += "--dart-define=BASA_CLOUD_URL=$CloudUrl" }
if ($CloudKey) { $defines += "--dart-define=BASA_CLOUD_KEY=$CloudKey" }
if ($LanUrl) { $defines += "--dart-define=BASA_LAN_URL=$LanUrl" }
if ($LanKey) { $defines += "--dart-define=BASA_LAN_KEY=$LanKey" }

function Invoke-Step([string]$what, [scriptblock]$cmd) {
    Write-Host "== $what"
    & $cmd
    if ($LASTEXITCODE -ne 0) { Write-Host "$what failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Invoke-Step 'Import walk (tutor entries reach no admin file)' { dart run tool/check_tutor_imports.dart }
Invoke-Step 'ViewModel boundary (commands and ui import only ViewModels and models)' { dart run tool/check_vm_boundary.dart }

$apkOut = 'build\app\outputs\flutter-apk'
$winOut = 'build\windows\x64\runner\Release'
$variants = @(@{ Name = 'admin'; Entry = 'lib/main.dart' }, @{ Name = 'tutor'; Entry = 'lib/main_tutor.dart' })

# Scan builds FIRST (never shipped): console commands compiled in, so each
# build holds every ViewModel method it can call. Android arm64 only: the Dart
# code is the same on every platform. They share Flutter's output name with the
# shipped APKs, so the shipped builds below overwrite them there; only
# build\scan keeps them.
$scan = 'build\scan'
if (Test-Path $scan) { Remove-Item -Recurse -Force $scan }
New-Item -ItemType Directory -Force $scan | Out-Null
foreach ($v in $variants) {
    $n = $v.Name
    Invoke-Step "Scan build $n" { flutter build apk --release --flavor $n -t $v.Entry --target-platform android-arm64 --dart-define=BASA_SCAN_BUILD=true @defines }
    Copy-Item "$apkOut\app-$n-release.apk" "$scan\basa-$n-scan.apk"
}

# Shipped builds.
$dist = 'build\dist'
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force $dist | Out-Null
foreach ($v in $variants) {
    $n = $v.Name
    Invoke-Step "Android $n" { flutter build apk --release --flavor $n -t $v.Entry @defines }
    Copy-Item "$apkOut\app-$n-release.apk" "$dist\basa-$n.apk"
    # Windows has no flavors: both entries build into the same folder, so copy
    # each one out right after its build.
    Invoke-Step "Windows $n" { flutter build windows --release -t $v.Entry @defines }
    Copy-Item -Recurse $winOut "$dist\windows-$n"
}

Invoke-Step 'Shipped builds: admin ViewModels only in admin, no debug console anywhere' {
    dart run tool/scan_markers.dart --markers tool/admin_markers.txt --admin-section admin-release --debug-section debug `
        --tutor "$dist\basa-tutor.apk" "$dist\windows-tutor\data\app.so" `
        --admin "$dist\basa-admin.apk" "$dist\windows-admin\data\app.so"
}
# The scan builds have the console, so the [debug] markers must be found there:
# that proves they are spelled right and survive compilation, which the
# shipped-build check above (absence only) can't.
Invoke-Step 'Scan builds: admin methods only in admin; console markers present' {
    dart run tool/scan_markers.dart --markers tool/admin_markers.txt --admin-section admin --present-section debug `
        --tutor "$scan\basa-tutor-scan.apk" --admin "$scan\basa-admin-scan.apk"
}

Write-Host '== Sizes'
foreach ($f in @("$dist\basa-admin.apk", "$dist\basa-tutor.apk")) {
    Write-Host ('{0,-28} {1,6:N1} MB' -f (Split-Path -Leaf $f), ((Get-Item $f).Length / 1MB))
}
foreach ($n in @('admin', 'tutor')) {
    Write-Host ('{0,-28} {1,6:N1} MB' -f "windows-$n\data\app.so", ((Get-Item "$dist\windows-$n\data\app.so").Length / 1MB))
}
Write-Host "Done: build\dist"
