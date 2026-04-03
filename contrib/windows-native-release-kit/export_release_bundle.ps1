$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
$bundleDir = Join-Path $scriptDir 'bundle'
$sourceDir = Join-Path $bundleDir 'source'
$docsDir = Join-Path $bundleDir 'docs'
$fileList = Join-Path $scriptDir 'changed-files.txt'

if (Test-Path $bundleDir) {
    Remove-Item -Recurse -Force $bundleDir
}

New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
New-Item -ItemType Directory -Force -Path $docsDir | Out-Null

$relativePaths = Get-Content $fileList | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($relativePath in $relativePaths) {
    $src = Join-Path $repoRoot $relativePath
    if (-not (Test-Path $src)) {
        Write-Warning "Skipping missing file: $relativePath"
        continue
    }

    $dest = Join-Path $sourceDir $relativePath
    $destParent = Split-Path -Parent $dest
    if ($destParent) {
        New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dest -Force
}

$docFiles = @(
    'README.md',
    'github-publish-guide-zh.md',
    'publish-checklist-zh.md',
    'windows-native-change-summary-en.md',
    'upstream-email-template-en.md',
    'README-template-en.md'
)

foreach ($docFile in $docFiles) {
    Copy-Item -LiteralPath (Join-Path $scriptDir $docFile) -Destination (Join-Path $docsDir $docFile) -Force
}

Write-Host "Release bundle created at: $bundleDir"
