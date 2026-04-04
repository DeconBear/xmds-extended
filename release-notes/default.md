# XMDS Extended Release

This release publishes the latest Windows portable installer for `xmds-extended`.

Highlights:

- native Windows XMDS execution without MSYS or WSL
- portable installer with bundled MinGW toolchain payload
- `run_xmds` and `run_plot` launchers for installed environments
- GitHub Release delivery for the Windows zip package

Windows install:

1. Download the `xmds-extended-windows-portable-*.zip` asset.
2. Extract it to a temporary directory.
3. Run `powershell -ExecutionPolicy Bypass -File .\install_windows.ps1`.
4. Choose a short install directory such as `D:\xmds`.

This installer currently expects Conda or Miniforge to already be available on the target machine.
