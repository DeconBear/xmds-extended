# XMDS2 Native Windows Compatibility

This repository contains an unofficial compatibility branch / patch set for running XMDS2 natively on Windows without MSYS or WSL.

## Upstream

XMDS2 is the original upstream project.

- Project page: https://sourceforge.net/projects/xmds/
- Documentation: https://xmds.sourceforge.net/

This repository is not the official XMDS2 repository.

## Scope

The work here focuses on:

- native Windows build compatibility
- native Windows runtime compatibility
- Python 3.12 and 3.13 compatibility
- regression test execution from native PowerShell
- Windows user documentation

## Validation

Validated items include:

- `python bin\\xmds2 examples\\lorenz.xmds`
- `.\lorenz.cmd`
- multiple top-level regression groups
- rerun of a user example with numerically consistent results against Linux output

## Licensing

XMDS2 remains copyrighted by its original authors.

This repository preserves the original `COPYING` and `COPYRIGHT` files from XMDS2. Please refer to those files for the governing license terms.
