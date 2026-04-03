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

## Documentation

- Windows usage guide: `docs/windows-native-guide-zh.md`
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
