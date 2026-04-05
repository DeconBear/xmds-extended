# xmds-extended

[English](README.md) | [Chinese (简体中文)](README-zh.md)

[Project Site](https://deconbear.github.io/xmds-extended/) | [项目网站](https://deconbear.github.io/xmds-extended/zh/)

`xmds-extended` is an unofficial derivative of XMDS2 focused on practical cross-platform maintenance, with native Windows support as the first major downstream addition.

## Upstream origin

This repository is derived from the XMDS2 project.

- Upstream project page: https://sourceforge.net/projects/xmds/
- Upstream documentation: https://xmds.sourceforge.net/

This repository is not the official XMDS2 repository.

## What this fork currently adds

- native Windows support without MSYS or WSL
- portable Windows installer and release packaging
- upgrade and uninstall flows for Windows portable installs
- CI for Windows, Linux, and macOS
- bilingual project pages and tutorial material

## Windows quick start

The recommended Windows entry point is the GitHub Release asset:

1. Download the latest `xmds-extended-windows-portable-*.zip` from Releases.
2. Extract the zip to a temporary directory.
3. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
   ```

4. Choose a short install directory such as `D:\xmds`.
5. Optionally add the install directory to `PATH`.

After installation:

- Compile and run from any directory:

  ```powershell
  run_xmds C:\path\to\simulation.xmds
  ```

- Upgrade in place by rerunning `install_windows.ps1` and choosing the same install directory.
- Uninstall with:

  ```powershell
  uninstall_xmds
  ```

This portable installer currently expects Conda or Miniforge to already be available on the target machine.

## Tutorials

Complete bilingual tutorials for this repository live under [`tutorials/`](tutorials/):

- English tutorial: [`tutorials/README.md`](tutorials/README.md)
- Chinese tutorial: [`tutorials/README-zh.md`](tutorials/README-zh.md)

The tutorials combine XMDS official documentation with the current workflow of this fork, including portable Windows installation, `run_xmds`, upgrade, uninstall, and learning paths based on the upstream examples.

## GitHub Pages

This repository publishes a bilingual project site through GitHub Pages:

- English: https://deconbear.github.io/xmds-extended/
- Chinese: https://deconbear.github.io/xmds-extended/zh/

The Pages site introduces the fork, links to releases, and provides a quick tutorial entry point in both languages.

## Automation

GitHub Actions currently handles:

- cross-platform CI on Windows, Linux, and macOS
- Windows portable package generation
- GitHub Release publishing for `v*` tags
- GitHub Pages deployment from the `site/` directory

Release notes are maintained in [`release-notes/`](release-notes/).

## Licensing and attribution

XMDS2 remains the upstream project and the original codebase is credited to its original authors.

This repository preserves the original XMDS2 licensing and copyright notices:

- [`COPYING`](COPYING)
- [`COPYRIGHT`](COPYRIGHT)

Please refer to those files for the governing terms.
