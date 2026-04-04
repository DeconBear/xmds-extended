[CmdletBinding()]
param(
    [string]$OutputDir = 'dist',
    [string]$PackageVersion = 'v1',
    [string]$ToolchainSource = 'D:\mingw64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
}
else {
    $OutputDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))
}
$PackageName = "xmds-extended-windows-portable-$PackageVersion"
$PackageRoot = Join-Path $OutputDir $PackageName
$PayloadRoot = Join-Path $PackageRoot 'payload'
$AppPayloadRoot = Join-Path $PayloadRoot 'app'
$ToolchainPayloadRoot = Join-Path $PayloadRoot 'toolchain'
$ManifestRoot = Join-Path $PayloadRoot 'manifests'
$ZipPath = Join-Path $OutputDir "$PackageName.zip"
$InstallerSource = Join-Path $PSScriptRoot 'install_windows.ps1'

$sourceItems = @(
    'bin',
    'docs',
    'documentation',
    'examples',
    'man',
    'testsuite',
    'xpdeint',
    'README.md',
    'COPYING',
    'COPYRIGHT',
    'Makefile',
    'ReleaseNotes',
    'run_tests.py',
    'setup.py'
)

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-AppRevision {
    try {
        $revision = (& git -C $RepoRoot rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0) {
            return $revision.Trim()
        }
    }
    catch {
    }

    return ''
}

function Write-QuickstartReadme {
    param([string]$Path)

    $contents = @'
XMDS Extended Windows Portable Package

Quick start:

1. Extract this zip to any temporary directory.
2. Open PowerShell in the extracted directory.
3. Run:

   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1

4. Follow the prompts to choose an install directory and whether to add run_xmds to PATH.

Notes:

- This first portable installer expects an existing Conda or Miniforge installation on the target machine.
- The zip already contains a bundled MinGW toolchain, so the installer only creates the Python runtime locally.
- Choose a short install directory. Deep install paths can break the bundled MinGW toolchain on Windows.

After installation:

- Without PATH integration:
  <InstallDir>\run_xmds.cmd C:\path\to\simulation.xmds

- With PATH integration:
  run_xmds C:\path\to\simulation.xmds
'@

    Set-Content -LiteralPath $Path -Value $contents -Encoding ASCII
}

Ensure-Directory -Path $OutputDir

if (Test-Path -LiteralPath $PackageRoot) {
    Remove-Item -LiteralPath $PackageRoot -Recurse -Force
}

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

Ensure-Directory -Path $PackageRoot
Ensure-Directory -Path $PayloadRoot
Ensure-Directory -Path $AppPayloadRoot
Ensure-Directory -Path $ToolchainPayloadRoot
Ensure-Directory -Path $ManifestRoot

Copy-Item -LiteralPath $InstallerSource -Destination (Join-Path $PackageRoot 'install_windows.ps1') -Force

foreach ($item in $sourceItems) {
    $sourcePath = Join-Path $RepoRoot $item
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Expected source item not found: $sourcePath"
    }

    Copy-Item -LiteralPath $sourcePath -Destination $AppPayloadRoot -Recurse -Force
}

if (-not (Test-Path -LiteralPath $ToolchainSource)) {
    throw "Bundled toolchain source was not found: $ToolchainSource"
}

Copy-Item -LiteralPath $ToolchainSource -Destination (Join-Path $ToolchainPayloadRoot 'mingw64') -Recurse -Force

$manifest = [ordered]@{
    package = [ordered]@{
        name = 'xmds-extended-windows-portable'
        version = $PackageVersion
        created_at = (Get-Date).ToString('s')
        app_revision = (Get-AppRevision)
    }
    runtime = [ordered]@{
        conda_packages = @(
            'python=3.11',
            'cheetah3',
            'pyparsing!=2.0.0',
            'mpmath',
            'numpy',
            'lxml',
            'h5py',
            'hdf5',
            'fftw',
            'setuptools'
        )
    }
    app = [ordered]@{
        source_items = $sourceItems
        entry_points = @(
            'run_xmds.cmd',
            'run_plot.cmd'
        )
    }
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ManifestRoot 'install-manifest.json') -Encoding UTF8
Write-QuickstartReadme -Path (Join-Path $PackageRoot 'README.txt')

Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host "Portable package root: $PackageRoot"
Write-Host "Portable package zip:  $ZipPath"
