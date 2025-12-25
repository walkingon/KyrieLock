Write-Host "Building Rust library for Android..." -ForegroundColor Cyan

Set-Location rust_crypto

Write-Host "Building for arm64-v8a (aarch64-linux-android)..." -ForegroundColor Yellow
cargo ndk -t arm64-v8a build --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build for arm64-v8a" -ForegroundColor Red
    Set-Location ..
    exit $LASTEXITCODE
}

Set-Location ..

Write-Host "Copying libraries to jniLibs..." -ForegroundColor Yellow
$jniLibsPath = "android\app\src\main\jniLibs\arm64-v8a"
New-Item -ItemType Directory -Force -Path $jniLibsPath | Out-Null
Copy-Item -Path "rust_crypto\target\aarch64-linux-android\release\librust_crypto.so" -Destination $jniLibsPath -Force

Write-Host "Android Rust library build complete!" -ForegroundColor Green
