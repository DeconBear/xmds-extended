[CmdletBinding()]
param(
    [string]$InstallDir,
    [ValidateSet('Prompt', 'Yes', 'No')]
    [string]$AddToPath = 'Prompt',
    [string]$CondaCommand,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InstallerRoot = Split-Path -Parent $PSCommandPath
$PayloadRoot = Join-Path $InstallerRoot 'payload'
$AppPayloadRoot = Join-Path $PayloadRoot 'app'
$ToolchainPayloadRoot = Join-Path $PayloadRoot 'toolchain'
$ManifestPath = Join-Path $PayloadRoot 'manifests\install-manifest.json'
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA 'XMDS-Extended'
$MaxPortableInstallPathLength = 100

function Write-Section {
    param([string]$Message)
    Write-Host ''
    Write-Host "== $Message =="
}

function Read-InputOrDefault {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )

    if ($NonInteractive) {
        return $DefaultValue
    }

    $rawValue = Read-Host "$Prompt [default: $DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return $DefaultValue
    }

    return $rawValue.Trim()
}

function Read-YesNoPrompt {
    param(
        [string]$Prompt,
        [bool]$DefaultValue
    )

    if ($NonInteractive) {
        return $DefaultValue
    }

    $suffix = if ($DefaultValue) { '[Y/n]' } else { '[y/N]' }
    $rawValue = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return $DefaultValue
    }

    switch ($rawValue.Trim().ToLowerInvariant()) {
        'y' { return $true }
        'yes' { return $true }
        'n' { return $false }
        'no' { return $false }
        default { throw "Unsupported response '$rawValue'. Please answer yes or no." }
    }
}

function Resolve-CondaCommand {
    param([string]$PreferredCommand)

    $candidates = @()

    if ($PreferredCommand) {
        $candidates += $PreferredCommand
    }

    $condaCommand = Get-Command conda -ErrorAction SilentlyContinue
    if ($condaCommand) {
        $candidates += $condaCommand.Source
    }

    $candidates += @(
        (Join-Path $env:USERPROFILE 'anaconda3\condabin\conda.bat'),
        (Join-Path $env:USERPROFILE 'miniconda3\condabin\conda.bat'),
        (Join-Path $env:USERPROFILE 'miniforge3\condabin\conda.bat'),
        (Join-Path $env:USERPROFILE 'mambaforge\condabin\conda.bat')
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not $candidate) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to find a usable conda command. Install Conda/Miniforge first, or pass -CondaCommand explicitly."
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-ItemTreeIfMissing {
    param(
        [string]$SourcePath,
        [string]$TargetRoot
    )

    $item = Get-Item -LiteralPath $SourcePath -Force
    $destination = Join-Path $TargetRoot $item.Name

    if ($item.PSIsContainer) {
        Ensure-Directory -Path $destination
        foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) {
            Copy-ItemTreeIfMissing -SourcePath $child.FullName -TargetRoot $destination
        }
        return
    }

    if (-not (Test-Path -LiteralPath $destination)) {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
    }
}

function Assert-SafePortableInstallPath {
    param(
        [string]$Path,
        [int]$MaxLength
    )

    if ($Path.Length -gt $MaxLength) {
        throw "The selected install directory is too deep for the bundled MinGW toolchain: '$Path' ($($Path.Length) characters). Choose a shorter path such as '$DefaultInstallDir' or 'C:\XMDS-Extended'."
    }
}

function Copy-PayloadDirectory {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot
    )

    Ensure-Directory -Path $TargetRoot

    foreach ($item in Get-ChildItem -LiteralPath $SourceRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $TargetRoot -Recurse -Force
    }
}

function Invoke-Conda {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Conda command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
    }
}

function Ensure-RuntimeEnvironment {
    param(
        [string]$RuntimeDir,
        [string]$Executable,
        [string[]]$PackageSpecs,
        [ValidateSet('Create', 'Reuse', 'Rebuild')]
        [string]$Mode = 'Create'
    )

    $pythonExe = Join-Path $RuntimeDir 'python.exe'
    if ($Mode -eq 'Reuse' -and (Test-Path -LiteralPath $pythonExe)) {
        Write-Host "Reusing existing runtime at $RuntimeDir"
        return
    }

    if ($Mode -eq 'Rebuild' -and (Test-Path -LiteralPath $RuntimeDir)) {
        Write-Host "Rebuilding runtime at $RuntimeDir"
        Remove-Item -LiteralPath $RuntimeDir -Recurse -Force
    }

    Write-Section "Creating runtime environment"

    $createArguments = @(
        'create',
        '-y',
        '-p', $RuntimeDir,
        '--override-channels',
        '-c', 'https://conda.anaconda.org/conda-forge'
    ) + $PackageSpecs

    try {
        Invoke-Conda -Executable $Executable -Arguments $createArguments
    }
    catch {
        Write-Warning 'Online runtime creation failed. Retrying from the local Conda package cache.'
        if (Test-Path -LiteralPath $RuntimeDir) {
            Remove-Item -LiteralPath $RuntimeDir -Recurse -Force
        }

        $offlineArguments = @(
            'create',
            '-y',
            '-p', $RuntimeDir,
            '--offline'
        ) + $PackageSpecs

        Invoke-Conda -Executable $Executable -Arguments $offlineArguments
    }
}

function Ensure-Hdf5ImportLibraries {
    param(
        [string]$RuntimeDir,
        [string]$ToolchainDir
    )

    $mingwBin = Join-Path $ToolchainDir 'bin'
    $libDir = Join-Path $RuntimeDir 'Library\lib'
    $dllDir = Join-Path $RuntimeDir 'Library\bin'
    $gendef = Join-Path $mingwBin 'gendef.exe'
    $dlltool = Join-Path $mingwBin 'dlltool.exe'

    if (-not (Test-Path -LiteralPath $gendef) -or -not (Test-Path -LiteralPath $dlltool)) {
        throw "MinGW helper tools were not found under $mingwBin"
    }

    Push-Location $libDir
    try {
        foreach ($dllName in @('hdf5', 'hdf5_hl')) {
            $dllPath = Join-Path $dllDir "$dllName.dll"
            $importLibrary = Join-Path $libDir "lib$dllName.dll.a"
            $definitionFile = Join-Path $libDir "$dllName.def"

            if (-not (Test-Path -LiteralPath $dllPath)) {
                throw "Expected runtime DLL not found: $dllPath"
            }

            if (Test-Path -LiteralPath $importLibrary) {
                continue
            }

            & $gendef $dllPath
            if ($LASTEXITCODE -ne 0) {
                throw "gendef failed for $dllPath"
            }

            & $dlltool -d "$dllName.def" -D "$dllName.dll" -l "lib$dllName.dll.a"
            if ($LASTEXITCODE -ne 0) {
                throw "dlltool failed for $dllName"
            }

            if (Test-Path -LiteralPath $definitionFile) {
                Remove-Item -LiteralPath $definitionFile -Force
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Merge-ToolchainHeadersIntoRuntimeInclude {
    param(
        [string]$RuntimeDir,
        [string]$ToolchainDir
    )

    $sourceInclude = Join-Path $ToolchainDir 'x86_64-w64-mingw32\include'
    $targetInclude = Join-Path $RuntimeDir 'Library\include'

    if (-not (Test-Path -LiteralPath $sourceInclude)) {
        throw "Bundled MinGW include directory was not found: $sourceInclude"
    }

    Ensure-Directory -Path $targetInclude

    foreach ($item in Get-ChildItem -LiteralPath $sourceInclude -Force) {
        Copy-ItemTreeIfMissing -SourcePath $item.FullName -TargetRoot $targetInclude
    }
}

function Get-UserPathEntries {
    $currentPath = (Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
    if (-not $currentPath) {
        return @()
    }

    return @($currentPath.Split(';') | Where-Object { $_ -and $_.Trim() })
}

function Add-InstallDirToUserPath {
    param([string]$PathEntry)

    $entries = Get-UserPathEntries
    $filteredEntries = @(
        $entries | Where-Object {
            -not [string]::Equals($_.TrimEnd('\'), $PathEntry.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    $newPath = (@($PathEntry) + $filteredEntries) -join ';'
    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value $newPath

    $signature = @'
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd,
    uint Msg,
    UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out UIntPtr lpdwResult
  );
}
'@

    if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
        Add-Type $signature
    }

    [UIntPtr]$result = [UIntPtr]::Zero
    [void][NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$result)
}

function Remove-InstallDirFromUserPath {
    param([string]$PathEntry)

    $entries = Get-UserPathEntries
    $filteredEntries = @(
        $entries | Where-Object {
            -not [string]::Equals($_.TrimEnd('\'), $PathEntry.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value ($filteredEntries -join ';')

    $signature = @'
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd,
    uint Msg,
    UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out UIntPtr lpdwResult
  );
}
'@

    if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
        Add-Type $signature
    }

    [UIntPtr]$result = [UIntPtr]::Zero
    [void][NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$result)
}

function Get-StringHash {
    param([string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant())
}

function Get-RuntimeSpecHash {
    param([string[]]$PackageSpecs)

    return (Get-StringHash -Value (($PackageSpecs | ForEach-Object { [string]$_ }) -join "`n"))
}

function Get-ExistingInstallState {
    param([string]$StateFile)

    if (-not (Test-Path -LiteralPath $StateFile)) {
        return $null
    }

    return (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json)
}

function Get-ManagedInstallItems {
    param([string]$InstallRoot)

    return @(
        (Join-Path $InstallRoot 'app'),
        (Join-Path $InstallRoot 'toolchain'),
        (Join-Path $InstallRoot 'runtime'),
        (Join-Path $InstallRoot 'run_xmds.cmd'),
        (Join-Path $InstallRoot 'run_xmds.ps1'),
        (Join-Path $InstallRoot 'run_plot.cmd'),
        (Join-Path $InstallRoot 'run_plot.ps1'),
        (Join-Path $InstallRoot 'uninstall_xmds.cmd'),
        (Join-Path $InstallRoot 'uninstall_windows.ps1')
    )
}

function Move-ItemsToBackup {
    param(
        [string[]]$ItemPaths,
        [string]$BackupRoot
    )

    $movedItems = @()
    foreach ($itemPath in $ItemPaths) {
        if (-not (Test-Path -LiteralPath $itemPath)) {
            continue
        }

        $leafName = Split-Path -Leaf $itemPath
        $destination = Join-Path $BackupRoot $leafName
        Move-Item -LiteralPath $itemPath -Destination $destination -Force
        $movedItems += [pscustomobject]@{
            original_path = $itemPath
            backup_path = $destination
        }
    }

    return ,$movedItems
}

function Restore-BackupItems {
    param([object[]]$MovedItems)

    foreach ($item in @($MovedItems) | Sort-Object { $_.original_path.Length } -Descending) {
        if (-not (Test-Path -LiteralPath $item.backup_path)) {
            continue
        }

        if (Test-Path -LiteralPath $item.original_path) {
            Remove-Item -LiteralPath $item.original_path -Recurse -Force
        }

        Move-Item -LiteralPath $item.backup_path -Destination $item.original_path -Force
    }
}

function Get-RuntimeAction {
    param(
        [pscustomobject]$ExistingState,
        [string]$RuntimeDir,
        [string]$PythonVersion,
        [string]$SpecHash
    )

    $pythonExe = Join-Path $RuntimeDir 'python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        return 'Create'
    }

    if (-not $ExistingState) {
        return 'Rebuild'
    }

    if (-not ($ExistingState.PSObject.Properties.Name -contains 'runtime')) {
        return 'Rebuild'
    }

    $existingRuntime = $ExistingState.runtime
    if (-not $existingRuntime) {
        return 'Rebuild'
    }

    if (-not [string]::Equals([string]$existingRuntime.python_version, $PythonVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Rebuild'
    }

    if (-not [string]::Equals([string]$existingRuntime.spec_hash, $SpecHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Rebuild'
    }

    return 'Reuse'
}

function Write-LauncherFiles {
    param(
        [string]$InstallRoot,
        [bool]$AddInstallDirToPath
    )

    $runXmdsCmdPath = Join-Path $InstallRoot 'run_xmds.cmd'
    $runXmdsPs1Path = Join-Path $InstallRoot 'run_xmds.ps1'
    $runPlotCmdPath = Join-Path $InstallRoot 'run_plot.cmd'
    $runPlotPs1Path = Join-Path $InstallRoot 'run_plot.ps1'
    $uninstallCmdPath = Join-Path $InstallRoot 'uninstall_xmds.cmd'
    $uninstallPath = Join-Path $InstallRoot 'uninstall_windows.ps1'

    $runXmdsCmd = @'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_xmds.ps1" %*
'@

    $runPlotCmd = @'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_plot.ps1" %*
'@

    $uninstallCmd = @'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_windows.ps1" %*
'@

    $runXmdsPs1 = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-InstallState {
    param([string]$StateFile)

    if (-not (Test-Path -LiteralPath $StateFile)) {
        throw "Install state file was not found: $StateFile"
    }

    return (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json)
}

function Add-ProcessPathEntries {
    param([string[]]$Entries)

    $validEntries = @($Entries | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $env:PATH = ($validEntries + @($env:PATH)) -join ';'
}

function Clear-HostCondaEnvironment {
    foreach ($name in @(
        'CONDA_PREFIX',
        'CONDA_DEFAULT_ENV',
        'CONDA_PROMPT_MODIFIER',
        'CONDA_SHLVL',
        'CONDA_EXE',
        '_CE_M',
        '_CE_CONDA'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
}

function Ensure-Hdf5ImportLibraries {
    param(
        [string]$RuntimeDir,
        [string]$ToolchainDir
    )

    $mingwBin = Join-Path $ToolchainDir 'bin'
    $libDir = Join-Path $RuntimeDir 'Library\lib'
    $dllDir = Join-Path $RuntimeDir 'Library\bin'
    $gendef = Join-Path $mingwBin 'gendef.exe'
    $dlltool = Join-Path $mingwBin 'dlltool.exe'

    if (-not (Test-Path -LiteralPath $gendef) -or -not (Test-Path -LiteralPath $dlltool)) {
        throw "MinGW helper tools were not found under $mingwBin"
    }

    Push-Location $libDir
    try {
        foreach ($dllName in @('hdf5', 'hdf5_hl')) {
            $dllPath = Join-Path $dllDir "$dllName.dll"
            $importLibrary = Join-Path $libDir "lib$dllName.dll.a"
            $definitionFile = Join-Path $libDir "$dllName.def"

            if (-not (Test-Path -LiteralPath $dllPath)) {
                throw "Expected runtime DLL not found: $dllPath"
            }

            if (Test-Path -LiteralPath $importLibrary) {
                continue
            }

            & $gendef $dllPath
            if ($LASTEXITCODE -ne 0) {
                throw "gendef failed for $dllPath"
            }

            & $dlltool -d "$dllName.def" -D "$dllName.dll" -l "lib$dllName.dll.a"
            if ($LASTEXITCODE -ne 0) {
                throw "dlltool failed for $dllName"
            }

            if (Test-Path -LiteralPath $definitionFile) {
                Remove-Item -LiteralPath $definitionFile -Force
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Ensure-ToolchainHeadersAvailable {
    param(
        [string]$RuntimeDir,
        [string]$ToolchainDir
    )

    $sourceInclude = Join-Path $ToolchainDir 'x86_64-w64-mingw32\include'
    $targetInclude = Join-Path $RuntimeDir 'Library\include'
    $sentinel = Join-Path $targetInclude '_mingw_print_push.h'

    if (Test-Path -LiteralPath $sentinel) {
        return
    }

    foreach ($item in Get-ChildItem -LiteralPath $sourceInclude -Force) {
        Copy-ItemTreeIfMissing -SourcePath $item.FullName -TargetRoot $targetInclude
    }
}

function Ensure-XmdsConfigured {
    param(
        [string]$PythonExe,
        [string]$Xmds2,
        [string]$RuntimeDir,
        [string]$StateDir,
        [string]$XMDSHome,
        [string]$InstallRoot
    )

    $cacheFile = Join-Path $XMDSHome 'waf_configure\c4che\_cache.py'
    $runtimeRecord = Join-Path $StateDir 'runtime-prefix.txt'
    $includeDir = Join-Path $RuntimeDir 'Library\include'
    $libDir = Join-Path $RuntimeDir 'Library\lib'

    $needsConfigure = -not (Test-Path -LiteralPath $cacheFile)
    if (-not $needsConfigure) {
        if (-not (Test-Path -LiteralPath $runtimeRecord)) {
            $needsConfigure = $true
        }
        else {
            $recordedPrefix = (Get-Content -LiteralPath $runtimeRecord -Raw).Trim()
            if (-not [string]::Equals($recordedPrefix, $RuntimeDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $needsConfigure = $true
            }
        }
    }

    if (-not $needsConfigure) {
        return
    }

    Write-Host 'Running XMDS configuration for this installation...'
    Push-Location $InstallRoot
    try {
        & $PythonExe $Xmds2 --reconfigure --include-path $includeDir --lib-path $libDir
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        throw "XMDS reconfigure failed with exit code $LASTEXITCODE"
    }

    Set-Content -LiteralPath $runtimeRecord -Value $RuntimeDir -Encoding UTF8
}

$InstallRoot = $PSScriptRoot
$AppRoot = Join-Path $InstallRoot 'app'
$RuntimeDir = Join-Path $InstallRoot 'runtime'
$ToolchainDir = Join-Path $InstallRoot 'toolchain\mingw64'
$StateDir = Join-Path $InstallRoot 'state'
$StateFile = Join-Path $StateDir 'install.json'
$XMDSHome = Join-Path $StateDir 'xmds-home'
$PythonExe = Join-Path $RuntimeDir 'python.exe'
$Xmds2 = Join-Path $AppRoot 'bin\xmds2'
[void](Get-InstallState -StateFile $StateFile)

if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Runtime python was not found: $PythonExe"
}

if (-not (Test-Path -LiteralPath $ToolchainDir)) {
    throw "Bundled MinGW toolchain was not found: $ToolchainDir"
}

if (-not (Test-Path -LiteralPath $Xmds2)) {
    throw "XMDS entry script was not found: $Xmds2"
}

$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
if ([System.IO.Path]::GetExtension($resolvedScript).ToLowerInvariant() -ne '.xmds') {
    throw "run_xmds expects a .xmds file path."
}

New-Item -ItemType Directory -Force -Path $StateDir, $XMDSHome | Out-Null

Clear-HostCondaEnvironment
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
$env:PYTHONNOUSERSITE = '1'
Add-ProcessPathEntries -Entries @(
    (Join-Path $ToolchainDir 'bin'),
    (Join-Path $RuntimeDir 'Library\usr\bin'),
    (Join-Path $RuntimeDir 'Library\bin'),
    (Join-Path $RuntimeDir 'Scripts'),
    (Join-Path $RuntimeDir 'bin'),
    $RuntimeDir
)
Ensure-ToolchainHeadersAvailable -RuntimeDir $RuntimeDir -ToolchainDir $ToolchainDir
Ensure-Hdf5ImportLibraries -RuntimeDir $RuntimeDir -ToolchainDir $ToolchainDir

$env:XMDS_USER_DATA = $XMDSHome

Ensure-XmdsConfigured -PythonExe $PythonExe -Xmds2 $Xmds2 -RuntimeDir $RuntimeDir -StateDir $StateDir -XMDSHome $XMDSHome -InstallRoot $InstallRoot

$scriptDir = Split-Path -Parent $resolvedScript
$scriptName = Split-Path -Leaf $resolvedScript
$generatedLauncher = '.\' + [System.IO.Path]::GetFileNameWithoutExtension($scriptName) + '.cmd'
$exitCode = 0

Push-Location $scriptDir
try {
    & $PythonExe $Xmds2 $scriptName
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        if (-not (Test-Path -LiteralPath $generatedLauncher)) {
            throw "Expected generated launcher not found: $generatedLauncher"
        }

        & $generatedLauncher
        $exitCode = $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    exit $exitCode
}
'@

$runPlotPs1 = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PlotScript,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$PlotArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ProcessPathEntries {
    param([string[]]$Entries)

    $validEntries = @($Entries | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $env:PATH = ($validEntries + @($env:PATH)) -join ';'
}

function Clear-HostCondaEnvironment {
    foreach ($name in @(
        'CONDA_PREFIX',
        'CONDA_DEFAULT_ENV',
        'CONDA_PROMPT_MODIFIER',
        'CONDA_SHLVL',
        'CONDA_EXE',
        '_CE_M',
        '_CE_CONDA'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
}

$InstallRoot = $PSScriptRoot
$AppRoot = Join-Path $InstallRoot 'app'
$RuntimeDir = Join-Path $InstallRoot 'runtime'
$ToolchainDir = Join-Path $InstallRoot 'toolchain\mingw64'
$PythonExe = Join-Path $RuntimeDir 'python.exe'

if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Runtime python was not found: $PythonExe"
}

Clear-HostCondaEnvironment
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
$env:PYTHONNOUSERSITE = '1'
Add-ProcessPathEntries -Entries @(
    (Join-Path $RuntimeDir 'Library\usr\bin'),
    (Join-Path $RuntimeDir 'Library\bin'),
    (Join-Path $RuntimeDir 'Scripts'),
    (Join-Path $RuntimeDir 'bin'),
    $RuntimeDir
)
$env:PYTHONPATH = $AppRoot
$env:MPLBACKEND = 'Agg'

$resolvedScript = (Resolve-Path -LiteralPath $PlotScript).Path
$plotDir = Split-Path -Parent $resolvedScript
$plotName = Split-Path -Leaf $resolvedScript
$exitCode = 0

Push-Location $plotDir
try {
    & $PythonExe $plotName @PlotArgs
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    exit $exitCode
}
'@

    $uninstallPs1 = @'
[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-YesNoPrompt {
    param(
        [string]$Prompt,
        [bool]$DefaultValue
    )

    $suffix = if ($DefaultValue) { '[Y/n]' } else { '[y/N]' }
    $rawValue = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return $DefaultValue
    }

    switch ($rawValue.Trim().ToLowerInvariant()) {
        'y' { return $true }
        'yes' { return $true }
        'n' { return $false }
        'no' { return $false }
        default { throw "Unsupported response '$rawValue'. Please answer yes or no." }
    }
}

function Get-UserPathEntries {
    $currentPath = (Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
    if (-not $currentPath) {
        return @()
    }

    return @($currentPath.Split(';') | Where-Object { $_ -and $_.Trim() })
}

function Update-EnvironmentBroadcast {
    $signature = @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd,
    uint Msg,
    UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out UIntPtr lpdwResult
  );
}
"@

    if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
        Add-Type $signature
    }

    [UIntPtr]$result = [UIntPtr]::Zero
    [void][NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$result)
}

function Remove-UserPathEntry {
    param([string]$PathEntry)

    $entries = Get-UserPathEntries
    $filtered = @(
        $entries | Where-Object {
            -not [string]::Equals($_.TrimEnd('\'), $PathEntry.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value ($filtered -join ';')
    Update-EnvironmentBroadcast
}

$InstallRoot = $PSScriptRoot
$StateFile = Join-Path $InstallRoot 'state\install.json'
$installState = $null

if (Test-Path -LiteralPath $StateFile) {
    $installState = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
}

$confirmed = if ($Force) {
    $true
}
else {
    Read-YesNoPrompt -Prompt "Uninstall XMDS Extended from '$InstallRoot'?" -DefaultValue $false
}
if (-not $confirmed) {
    throw 'Uninstall cancelled by user.'
}

if ($installState -and $installState.add_install_dir_to_path) {
    Remove-UserPathEntry -PathEntry $InstallRoot
    Write-Host 'Removed the installation directory from the user PATH.'
}

$cleanupScript = Join-Path $env:TEMP ("xmds-uninstall-" + [guid]::NewGuid().ToString('N') + '.ps1')
$currentPid = $PID
$cleanupScriptContent = @"
param(
    [string]`$InstallRoot,
    [int]`$ParentPid
)

`$deadline = (Get-Date).AddMinutes(5)
while ((Get-Process -Id `$ParentPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt `$deadline) {
    Start-Sleep -Milliseconds 500
}

for (`$attempt = 0; `$attempt -lt 40; `$attempt++) {
    if (-not (Test-Path -LiteralPath `$InstallRoot)) {
        break
    }

    try {
        Remove-Item -LiteralPath `$InstallRoot -Recurse -Force
    }
    catch {
        Start-Sleep -Milliseconds 500
    }
}

Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
"@

Set-Content -LiteralPath $cleanupScript -Value $cleanupScriptContent -Encoding UTF8
Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $cleanupScript,
    '-InstallRoot', $InstallRoot,
    '-ParentPid', $currentPid
) -WindowStyle Hidden

Write-Host 'Scheduled background cleanup of the installation directory.'
Write-Host 'You can close this terminal now.'
'@

    Set-Content -LiteralPath $runXmdsCmdPath -Value $runXmdsCmd -Encoding ASCII
    Set-Content -LiteralPath $runXmdsPs1Path -Value $runXmdsPs1 -Encoding UTF8
    Set-Content -LiteralPath $runPlotCmdPath -Value $runPlotCmd -Encoding ASCII
    Set-Content -LiteralPath $runPlotPs1Path -Value $runPlotPs1 -Encoding UTF8
    Set-Content -LiteralPath $uninstallCmdPath -Value $uninstallCmd -Encoding ASCII
    Set-Content -LiteralPath $uninstallPath -Value $uninstallPs1 -Encoding UTF8
}

function Write-InstallState {
    param(
        [string]$StateFile,
        [string]$InstallRoot,
        [string]$RuntimeDir,
        [string]$ToolchainDir,
        [bool]$AddInstallDirToPath,
        [pscustomobject]$Manifest,
        [string]$InstallMode,
        [string]$RuntimeSpecHash,
        [string]$RuntimePythonVersion,
        [string]$RuntimeAction,
        [pscustomobject]$PreviousState,
        [string]$BackupRoot
    )

    $state = [ordered]@{
        installed_at = (Get-Date).ToString('s')
        install_mode = $InstallMode
        install_dir = $InstallRoot
        runtime_dir = $RuntimeDir
        toolchain_dir = $ToolchainDir
        add_install_dir_to_path = $AddInstallDirToPath
        uninstall_command = (Join-Path $InstallRoot 'uninstall_xmds.cmd')
        package = [ordered]@{
            name = $Manifest.package.name
            version = $Manifest.package.version
            app_revision = $Manifest.package.app_revision
        }
        runtime = [ordered]@{
            python_version = $RuntimePythonVersion
            spec_hash = $RuntimeSpecHash
            provisioner_version = '1'
            action = $RuntimeAction
        }
        history = [ordered]@{
            previous_version = if ($PreviousState) { [string]$PreviousState.package.version } else { '' }
            previous_app_revision = if ($PreviousState) { [string]$PreviousState.package.app_revision } else { '' }
            last_upgrade_at = if ($InstallMode -eq 'upgrade') { (Get-Date).ToString('s') } else { '' }
            backup_root = $BackupRoot
        }
    }

    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $AppPayloadRoot)) {
    throw "Installer payload directory was not found: $AppPayloadRoot"
}

if (-not (Test-Path -LiteralPath $ToolchainPayloadRoot)) {
    throw "Bundled toolchain payload directory was not found: $ToolchainPayloadRoot"
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Installer manifest was not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

Write-Host "XMDS Windows Portable Installer $($manifest.package.version)"

$InstallDir = if ($InstallDir) { $InstallDir } else { Read-InputOrDefault -Prompt 'Install directory' -DefaultValue $DefaultInstallDir }
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
Assert-SafePortableInstallPath -Path $InstallDir -MaxLength $MaxPortableInstallPathLength
$AppInstallRoot = Join-Path $InstallDir 'app'
$ToolchainInstallRoot = Join-Path $InstallDir 'toolchain'
$BundledToolchainDir = Join-Path $ToolchainInstallRoot 'mingw64'
$RuntimeDir = Join-Path $InstallDir 'runtime'
$StateDir = Join-Path $InstallDir 'state'
$StateFile = Join-Path $StateDir 'install.json'
$PackageSpecs = @($manifest.runtime.conda_packages | ForEach-Object { [string]$_ })
$RuntimePythonVersion = if ($manifest.runtime.python_version) { [string]$manifest.runtime.python_version } else { '3.11' }
$RuntimeSpecHash = Get-RuntimeSpecHash -PackageSpecs $PackageSpecs
$ExistingState = Get-ExistingInstallState -StateFile $StateFile
$InstallMode = 'fresh'

if (Test-Path -LiteralPath $InstallDir) {
    $existingEntries = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
    if ($existingEntries.Count -gt 0) {
        if ($ExistingState) {
            $InstallMode = 'upgrade'
        }
        else {
            $continueInstall = Read-YesNoPrompt -Prompt "Install directory '$InstallDir' is not empty. Continue and overwrite managed files?" -DefaultValue $false
            if (-not $continueInstall) {
                throw 'Installation cancelled by user.'
            }
        }
    }
}

$defaultAddToPath = $true
if ($ExistingState -and ($ExistingState.PSObject.Properties.Name -contains 'add_install_dir_to_path')) {
    $defaultAddToPath = [bool]$ExistingState.add_install_dir_to_path
}

$ShouldAddToPath = switch ($AddToPath) {
    'Yes' { $true }
    'No' { $false }
    default { Read-YesNoPrompt -Prompt 'Add run_xmds command to PATH?' -DefaultValue $defaultAddToPath }
}

$RuntimeAction = Get-RuntimeAction -ExistingState $ExistingState -RuntimeDir $RuntimeDir -PythonVersion $RuntimePythonVersion -SpecHash $RuntimeSpecHash

Write-Section "Installation summary"
Write-Host "Mode: $InstallMode"
if ($ExistingState) {
    Write-Host "Current install version: $($ExistingState.package.version)"
}
Write-Host "Target version: $($manifest.package.version)"
Write-Host "Runtime action: $RuntimeAction"
Write-Host "Add install directory to PATH: $ShouldAddToPath"

$Proceed = Read-YesNoPrompt -Prompt 'Proceed with installation?' -DefaultValue $true
if (-not $Proceed) {
    throw 'Installation cancelled by user.'
}

$CondaCommand = $null
if ($RuntimeAction -ne 'Reuse') {
    $CondaCommand = Resolve-CondaCommand -PreferredCommand $CondaCommand
}

$BackupRoot = ''
$MovedItems = @()
$PreviousStateJson = if (Test-Path -LiteralPath $StateFile) { Get-Content -LiteralPath $StateFile -Raw } else { '' }

try {
    Write-Section "Preparing directories"
    Ensure-Directory -Path $InstallDir
    Ensure-Directory -Path $StateDir

    if ($InstallMode -eq 'upgrade') {
        $BackupRoot = Join-Path $StateDir ("backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Ensure-Directory -Path $BackupRoot

        $managedItems = Get-ManagedInstallItems -InstallRoot $InstallDir
        if ($RuntimeAction -eq 'Reuse') {
            $managedItems = @($managedItems | Where-Object { -not [string]::Equals($_, $RuntimeDir, [System.StringComparison]::OrdinalIgnoreCase) })
        }

        Write-Section "Backing up existing installation"
        $MovedItems = @(Move-ItemsToBackup -ItemPaths $managedItems -BackupRoot $BackupRoot)
    }

    Write-Section "Copying application payload"
    Copy-PayloadDirectory -SourceRoot $AppPayloadRoot -TargetRoot $AppInstallRoot

    Write-Section "Copying bundled toolchain"
    Copy-PayloadDirectory -SourceRoot $ToolchainPayloadRoot -TargetRoot $ToolchainInstallRoot

    Ensure-RuntimeEnvironment -RuntimeDir $RuntimeDir -Executable $CondaCommand -PackageSpecs $PackageSpecs -Mode $RuntimeAction
    Merge-ToolchainHeadersIntoRuntimeInclude -RuntimeDir $RuntimeDir -ToolchainDir $BundledToolchainDir
    Ensure-Hdf5ImportLibraries -RuntimeDir $RuntimeDir -ToolchainDir $BundledToolchainDir

    Write-Section "Writing launchers"
    Write-LauncherFiles -InstallRoot $InstallDir -AddInstallDirToPath $ShouldAddToPath

    if ($ShouldAddToPath) {
        Write-Section "Updating PATH"
        Add-InstallDirToUserPath -PathEntry $InstallDir
    }
    elseif ($ExistingState -and $ExistingState.add_install_dir_to_path) {
        Write-Section "Updating PATH"
        Remove-InstallDirFromUserPath -PathEntry $InstallDir
    }

    Write-InstallState `
        -StateFile $StateFile `
        -InstallRoot $InstallDir `
        -RuntimeDir $RuntimeDir `
        -ToolchainDir $BundledToolchainDir `
        -AddInstallDirToPath $ShouldAddToPath `
        -Manifest $manifest `
        -InstallMode $InstallMode `
        -RuntimeSpecHash $RuntimeSpecHash `
        -RuntimePythonVersion $RuntimePythonVersion `
        -RuntimeAction $RuntimeAction `
        -PreviousState $ExistingState `
        -BackupRoot $BackupRoot
}
catch {
    if ($MovedItems.Count -gt 0) {
        Write-Warning 'Installation failed. Restoring the previous installation.'
        Restore-BackupItems -MovedItems $MovedItems
    }

    if ($ExistingState -and $ExistingState.add_install_dir_to_path) {
        Remove-InstallDirFromUserPath -PathEntry $InstallDir
        Add-InstallDirToUserPath -PathEntry $InstallDir
    }
    else {
        Remove-InstallDirFromUserPath -PathEntry $InstallDir
    }

    if ($PreviousStateJson) {
        Ensure-Directory -Path $StateDir
        Set-Content -LiteralPath $StateFile -Value $PreviousStateJson -Encoding UTF8
    }
    elseif (Test-Path -LiteralPath $StateFile) {
        Remove-Item -LiteralPath $StateFile -Force
    }

    throw
}

Write-Section "Installation complete"
Write-Host "Install directory: $InstallDir"
Write-Host "Runtime directory: $RuntimeDir"
Write-Host ''
Write-Host 'Usage examples:'
Write-Host "  $InstallDir\run_xmds.cmd C:\path\to\simulation.xmds"
Write-Host "  $InstallDir\run_plot.cmd C:\path\to\plot_script.py"
Write-Host "  $InstallDir\uninstall_xmds.cmd"
if ($ShouldAddToPath) {
    Write-Host ''
    Write-Host 'Because the install directory was added to PATH, new terminals can also run:'
    Write-Host '  run_xmds C:\path\to\simulation.xmds'
    Write-Host '  uninstall_xmds'
}
