# xmds-extended

`xmds-extended` is an unofficial derivative of XMDS2 for continued development and practical use.

This repository currently focuses on making XMDS2 usable in a native Windows environment without MSYS or WSL, while leaving room for further downstream development and local extensions.

## Upstream origin

This codebase is derived from the XMDS2 project.

- Upstream project page: https://sourceforge.net/projects/xmds/
- Upstream documentation: https://xmds.sourceforge.net/

This repository is not the official XMDS2 repository.

## What this repository currently adds

- native Windows compatibility without MSYS or WSL
- build and runtime fixes for modern Python and native Windows toolchains
- regression test runner updates for native PowerShell
- Chinese documentation for Windows-native usage
- release and publishing material for maintaining this fork publicly

## Validation status

The current codebase has already been validated on native Windows, including:

- `python bin\xmds2 examples\lorenz.xmds`
- `.\lorenz.cmd`
- top-level regression groups executed individually from native PowerShell
- rerun of a user-provided example with numerically consistent results relative to prior Linux output

## Windows installation

For end users on Windows, the recommended entry point is the GitHub Release asset rather than cloning the repository directly.

Requirements:

- an existing Conda or Miniforge installation on the target machine
- a short install directory such as `D:\xmds` or `C:\XMDS-Extended`

Portable install flow:

1. Download the latest `xmds-extended-windows-portable-*.zip` asset from GitHub Releases.
2. Extract the zip to a temporary directory.
3. Open PowerShell in the extracted directory.
4. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
   ```

5. Choose an install directory and whether to add `run_xmds` to `PATH`.

After installation:

- If you added the install directory to `PATH`, open a new terminal and run:

  ```powershell
  run_xmds C:\path\to\simulation.xmds
  ```

- If you did not add it to `PATH`, run:

  ```powershell
  <InstallDir>\run_xmds.cmd C:\path\to\simulation.xmds
  ```

For plotting helpers:

```powershell
<InstallDir>\run_plot.cmd C:\path\to\plot_script.py
```

The detailed Windows installer design and upgrade plan are documented in `docs/`.

## Releases and automation

This repository uses GitHub Actions for Windows packaging:

- pushing to `main` runs CI and builds a Windows portable zip as a workflow artifact
- pushing a tag matching `v*` builds the same zip again, runs a Windows installer smoke test, and publishes the zip as a GitHub Release asset

The repository currently publishes Windows deliverables through GitHub Releases, not GitHub Packages.

## Documentation

- Windows usage guide: `docs/windows-native-guide-zh.md`
- Windows portable installer design: `docs/windows-portable-installer-design-zh.md`
- Windows portable upgrade design: `docs/windows-portable-upgrade-design-zh.md`
- GitHub release workflow notes: `docs/github-release-workflow-zh.md`
- fork publishing material: `contrib/windows-native-release-kit/`

## Repository layout

- `xpdeint/`: core XMDS2 code generation and support code
- `testsuite/`: regression and feature tests
- `examples/`: example XMDS2 scripts
- `docs/`: added local documentation for this fork
- `contrib/windows-native-release-kit/`: publishing and upstream submission helpers

## Licensing and attribution

XMDS2 remains the upstream project and the original codebase is credited to its original authors.

This repository preserves the original XMDS2 licensing and copyright notices:

- `COPYING`
- `COPYRIGHT`

Please refer to those files for the governing terms.

## Notes

- This repository should be understood as an unofficial fork / derivative work.
- Official XMDS2 project information should be taken from the upstream SourceForge pages.
- Additional downstream features may be developed here over time beyond Windows compatibility alone.
