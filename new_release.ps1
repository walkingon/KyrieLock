param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch '^v\d+\.\d+\.\d+\+\d+$') {
    Write-Error "Version format should be vX.Y.Z+N (e.g., v1.2.2+4)"
    exit 1
}

$VersionNumber = $Version.Substring(1)
$GitTag = $Version -replace '\+\d+$', ''

Write-Host "VersionNumber: $VersionNumber, GitTag: $GitTag"
Write-Host "Starting release process for $Version" -ForegroundColor Green

Write-Host "`n[1/4] Updating version in pubspec.yaml..." -ForegroundColor Yellow
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw
$pubspecContent = $pubspecContent -replace 'version:\s+[\d\.]+\+\d+', "version: $VersionNumber"
Set-Content -Path $pubspecPath -Value $pubspecContent -NoNewline
Write-Host "Version updated to $VersionNumber" -ForegroundColor Green

Write-Host "`n[2/4] Committing changes..." -ForegroundColor Yellow
git add .
git commit -m "Release $GitTag"
Write-Host "Changes committed" -ForegroundColor Green

Write-Host "`n[3/4] Creating and pushing tag..." -ForegroundColor Yellow
git tag $GitTag
Write-Host "Tag $GitTag created" -ForegroundColor Green

Write-Host "`n[4/4] Pushing to origin..." -ForegroundColor Yellow
git push origin main
git push origin $GitTag
Write-Host "Pushed to origin" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Release process completed successfully!" -ForegroundColor Green
Write-Host "GitHub Actions will now build the release automatically." -ForegroundColor Cyan
Write-Host "Check progress at: https://github.com/walkingon/KyrieLock/actions" -ForegroundColor Cyan
Write-Host "View releases at: https://github.com/walkingon/KyrieLock/releases" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan