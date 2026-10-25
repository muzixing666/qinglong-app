[CmdletBinding()]
param([switch]$DebugBuild, [switch]$Demo, [switch]$SplitAbi)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutter = Join-Path $root '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { throw 'Install the stable Flutter SDK under .tools/flutter first.' }
$env:JAVA_HOME = Join-Path $root '.tools\jdk'
$env:ANDROID_HOME = Join-Path $root '.tools\android-sdk'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
# The current Windows analyzer has an encoding bug with non-ASCII working paths.
$alias = Join-Path ([IO.Path]::GetPathRoot($root)) 'qinglong-workspace'
if (-not (Test-Path -LiteralPath $alias)) { New-Item -ItemType Junction -Path $alias -Target $root | Out-Null }
$target = (Get-Item -LiteralPath $alias).Target
if ([IO.Path]::GetFullPath([string]$target) -ne $root) { throw 'The ASCII workspace alias belongs to another directory.' }
& py (Join-Path $root 'scripts/prepare-flutter.py')
if($LASTEXITCODE -ne 0){ throw 'Native Flutter sources could not be synchronized.' }
Push-Location (Join-Path $alias 'flutter_app')
try {
    $version = [regex]::Match((Get-Content -LiteralPath 'pubspec.yaml' -Raw), '(?m)^version:\s*([^+\s]+)').Groups[1].Value
    if(-not $version){throw 'Missing Flutter app version.'}
    $argsList = @('build','apk', $(if($DebugBuild){'--debug'}else{'--release'}))
    if($Demo){ $argsList += '--dart-define=QL_DEMO_ONLY=true' }
    if($SplitAbi){ $argsList += '--split-per-abi' }
    & (Join-Path $alias '.tools\flutter\bin\flutter.bat') @argsList
    if($LASTEXITCODE -ne 0){ throw 'Flutter build failed.' }
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $variant = if($DebugBuild){'debug'}else{'release'}
    $suffix = if($Demo){'-demo'}else{''}
    if($DebugBuild){$suffix += '-debug'}
    if($SplitAbi){
        foreach($abi in @('armeabi-v7a','arm64-v8a','x86_64')) {
            Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-$abi-$variant.apk" -Destination (Join-Path $dist "qinglong-mobile-$version-flutter-$abi$suffix.apk") -Force
        }
    }else{
        Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-$variant.apk" -Destination (Join-Path $dist "qinglong-mobile-$version-flutter$suffix.apk") -Force
    }
}finally{Pop-Location}
