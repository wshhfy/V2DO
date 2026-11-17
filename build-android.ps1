param([switch]$UseGoogleMirror, [ValidateSet('release','profile','debug')][string]$Mode = 'release')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if ($UseGoogleMirror) {
  $env:GRADLE_USER_HOME = Join-Path $PSScriptRoot '.gradle-cache'
  $initDir = Join-Path $env:GRADLE_USER_HOME 'init.d'
  New-Item -ItemType Directory -Force $initDir | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'tooling\google-download.gradle') $initDir -Force
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter is not on PATH.' }
if (-not (Test-Path android)) {
  flutter create --platforms=android --project-name forum_app --org dev.dualforum .
  if ($LASTEXITCODE -ne 0) { throw 'Platform generation failed' }
}
$manifestPath = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
$manifest = Get-Content $manifestPath -Raw
if ($manifest -notmatch 'android.permission.INTERNET') {
  $manifest = $manifest.Replace('<application', '<uses-permission android:name="android.permission.INTERNET"/><application')
  Set-Content $manifestPath $manifest -Encoding utf8
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency download failed' }
flutter analyze lib
if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
flutter build apk "--$Mode"
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
Copy-Item "build\app\outputs\flutter-apk\app-$Mode.apk" "EXDO-$Mode.apk" -Force
