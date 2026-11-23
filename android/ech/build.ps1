param(
    [Parameter(Mandatory = $true)][string]$NdkPath,
    [string]$Go = 'go'
)
$ErrorActionPreference = 'Stop'
$compilerDir = Join-Path $NdkPath 'toolchains/llvm/prebuilt/windows-x86_64/bin'
$outputRoot = Join-Path $PSScriptRoot '../app/src/main/jniLibs'
$targets = @(
    @{ Abi = 'arm64-v8a'; Arch = 'arm64'; Compiler = 'aarch64-linux-android24-clang.cmd' },
    @{ Abi = 'armeabi-v7a'; Arch = 'arm'; Compiler = 'armv7a-linux-androideabi24-clang.cmd' },
    @{ Abi = 'x86_64'; Arch = 'amd64'; Compiler = 'x86_64-linux-android24-clang.cmd' }
)
Push-Location $PSScriptRoot
try {
    $env:GOOS = 'android'
    $env:CGO_ENABLED = '1'
    foreach ($target in $targets) {
        $env:GOARCH = $target.Arch
        $env:GOARM = if ($target.Arch -eq 'arm') { '7' } else { '' }
        $env:CC = Join-Path $compilerDir $target.Compiler
        $directory = Join-Path $outputRoot $target.Abi
        New-Item -ItemType Directory -Force $directory | Out-Null
        $output = Join-Path $directory 'libv2do_ech.so'
        & $Go build -trimpath -buildmode=c-shared -o $output .
        if ($LASTEXITCODE -ne 0) { throw "ECH build failed: $($target.Abi)" }
        $header = Join-Path $directory 'libv2do_ech.h'
        if (Test-Path -LiteralPath $header) { Remove-Item -LiteralPath $header }
    }
} finally {
    Pop-Location
}
