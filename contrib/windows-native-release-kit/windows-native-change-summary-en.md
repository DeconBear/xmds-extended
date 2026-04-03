# XMDS2 Native Windows Compatibility Summary

This work makes the current XMDS2 codebase usable in a native Windows environment without MSYS or WSL.

## Main changes

- Added compatibility fixes for Python 3.12 and 3.13, including legacy waf compatibility.
- Stabilized the Windows build path in `xpdeint/Configuration.py` and `xpdeint/support/wscript`.
- Added Windows-friendly runtime handling and launcher generation.
- Added compatibility shims for POSIX-specific code paths such as `bzero` and `gettimeofday`.
- Normalized generated source path handling for Windows.
- Updated test helpers so the regression suite can run from native PowerShell.
- Added Chinese documentation for native Windows usage.

## Validation completed

- `python bin\\xmds2 examples\\lorenz.xmds`
- `.\lorenz.cmd`
- Top-level regression groups passed individually:
  - `geometry`
  - `features`
  - `integrators`
  - `operators`
  - `vectors`
  - `transforms`
  - `io`
  - `stochastic`
  - `runtime_lattice`
  - `fast`
  - `openmp`
  - `mpi`
- A user-provided example in `test_example\\Morgan_01_20240523` was rebuilt and rerun on native Windows, with numerically consistent output compared against prior Ubuntu results.

## Redistribution note

XMDS2 remains the original upstream project. This work should be presented as an unofficial compatibility branch, patch set, or fork with original licensing retained.
