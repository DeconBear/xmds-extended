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
        [string[]]$PackageSpecs
    )

    $pythonExe = Join-Path $RuntimeDir 'python.exe'
    if (Test-Path -LiteralPath $pythonExe) {
        Write-Host "Reusing existing runtime at $RuntimeDir"
        return
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
        Copy-Item -LiteralPath $item.FullName -Destination $targetInclude -Recurse -Force
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

function Write-LauncherFiles {
    param([string]$InstallRoot)

    $runXmdsCmdPath = Join-Path $InstallRoot 'run_xmds.cmd'
    $runXmdsPs1Path = Join-Path $InstallRoot 'run_xmds.ps1'
    $runPlotCmdPath = Join-Path $InstallRoot 'run_plot.cmd'
    $runPlotPs1Path = Join-Path $InstallRoot 'run_plot.ps1'
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
        Copy-Item -LiteralPath $item.FullName -Destination $targetInclude -Recurse -Force
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
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-UserPathEntry {
    param([string]$PathEntry)

    $currentPath = (Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
    if (-not $currentPath) {
        return
    }

    $entries = @($currentPath.Split(';') | Where-Object { $_ -and $_.Trim() })
    $filtered = @(
        $entries | Where-Object {
            -not [string]::Equals($_.TrimEnd('\'), $PathEntry.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value ($filtered -join ';')
}

$InstallRoot = $PSScriptRoot
$StateFile = Join-Path $InstallRoot 'state\install.json'

if (Test-Path -LiteralPath $StateFile) {
    $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    if ($state.add_install_dir_to_path) {
        Remove-UserPathEntry -PathEntry $InstallRoot
        Write-Host 'Removed install directory from the user PATH.'
    }
}

Write-Host 'Delete this installation directory manually after closing the terminal if you no longer need it:'
Write-Host "  $InstallRoot"
'@

    Set-Content -LiteralPath $runXmdsCmdPath -Value $runXmdsCmd -Encoding ASCII
    Set-Content -LiteralPath $runXmdsPs1Path -Value $runXmdsPs1 -Encoding UTF8
    Set-Content -LiteralPath $runPlotCmdPath -Value $runPlotCmd -Encoding ASCII
    Set-Content -LiteralPath $runPlotPs1Path -Value $runPlotPs1 -Encoding UTF8
    Set-Content -LiteralPath $uninstallPath -Value $uninstallPs1 -Encoding UTF8
}

function Write-InstallState {
    param(
        [string]$StateFile,
        [string]$InstallRoot,
        [string]$RuntimeDir,
        [string]$ToolchainDir,
        [bool]$AddInstallDirToPath,
        [pscustomobject]$Manifest
    )

    $state = [ordered]@{
        installed_at = (Get-Date).ToString('s')
        install_dir = $InstallRoot
        runtime_dir = $RuntimeDir
        toolchain_dir = $ToolchainDir
        add_install_dir_to_path = $AddInstallDirToPath
        package = [ordered]@{
            name = $Manifest.package.name
            version = $Manifest.package.version
            app_revision = $Manifest.package.app_revision
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
$ShouldAddToPath = switch ($AddToPath) {
    'Yes' { $true }
    'No' { $false }
    default { Read-YesNoPrompt -Prompt 'Add run_xmds command to PATH?' -DefaultValue $true }
}

if (Test-Path -LiteralPath $InstallDir) {
    $existingEntries = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
    if ($existingEntries.Count -gt 0) {
        $existingState = Join-Path $InstallDir 'state\install.json'
        if (-not (Test-Path -LiteralPath $existingState)) {
            $continueInstall = Read-YesNoPrompt -Prompt "Install directory '$InstallDir' is not empty. Continue and overwrite managed files?" -DefaultValue $false
            if (-not $continueInstall) {
                throw 'Installation cancelled by user.'
            }
        }
    }
}

$Proceed = Read-YesNoPrompt -Prompt 'Proceed with installation?' -DefaultValue $true
if (-not $Proceed) {
    throw 'Installation cancelled by user.'
}

$CondaCommand = Resolve-CondaCommand -PreferredCommand $CondaCommand
$AppInstallRoot = Join-Path $InstallDir 'app'
$ToolchainInstallRoot = Join-Path $InstallDir 'toolchain'
$BundledToolchainDir = Join-Path $ToolchainInstallRoot 'mingw64'
$RuntimeDir = Join-Path $InstallDir 'runtime'
$StateDir = Join-Path $InstallDir 'state'
$StateFile = Join-Path $StateDir 'install.json'
$PackageSpecs = @($manifest.runtime.conda_packages | ForEach-Object { [string]$_ })

Write-Section "Preparing directories"
Ensure-Directory -Path $InstallDir
Ensure-Directory -Path $StateDir

Write-Section "Copying application payload"
Copy-PayloadDirectory -SourceRoot $AppPayloadRoot -TargetRoot $AppInstallRoot

Write-Section "Copying bundled toolchain"
Copy-PayloadDirectory -SourceRoot $ToolchainPayloadRoot -TargetRoot $ToolchainInstallRoot

Ensure-RuntimeEnvironment -RuntimeDir $RuntimeDir -Executable $CondaCommand -PackageSpecs $PackageSpecs
Merge-ToolchainHeadersIntoRuntimeInclude -RuntimeDir $RuntimeDir -ToolchainDir $BundledToolchainDir
Ensure-Hdf5ImportLibraries -RuntimeDir $RuntimeDir -ToolchainDir $BundledToolchainDir

Write-Section "Writing launchers"
Write-LauncherFiles -InstallRoot $InstallDir
Write-InstallState -StateFile $StateFile -InstallRoot $InstallDir -RuntimeDir $RuntimeDir -ToolchainDir $BundledToolchainDir -AddInstallDirToPath $ShouldAddToPath -Manifest $manifest

if ($ShouldAddToPath) {
    Write-Section "Updating PATH"
    Add-InstallDirToUserPath -PathEntry $InstallDir
}

Write-Section "Installation complete"
Write-Host "Install directory: $InstallDir"
Write-Host "Runtime directory: $RuntimeDir"
Write-Host ''
Write-Host 'Usage examples:'
Write-Host "  $InstallDir\run_xmds.cmd C:\path\to\simulation.xmds"
Write-Host "  $InstallDir\run_plot.cmd C:\path\to\plot_script.py"
if ($ShouldAddToPath) {
    Write-Host ''
    Write-Host 'Because the install directory was added to PATH, new terminals can also run:'
    Write-Host '  run_xmds C:\path\to\simulation.xmds'
}
