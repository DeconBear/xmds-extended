Subject: [PATCH] Native Windows compatibility improvements for XMDS2

Hello XMDS2 maintainers,

I have prepared a set of changes to improve native Windows support for XMDS2 without relying on MSYS or WSL.

The work covers:

- Python 3.12 and 3.13 compatibility updates
- legacy waf compatibility fixes
- Windows build and runtime adjustments
- HDF5 and FFTW detection improvements for native Windows setups
- POSIX compatibility shims needed by generated code
- test runner updates for native PowerShell use
- documentation for native Windows usage

Validation completed on Windows includes:

- `python bin\\xmds2 examples\\lorenz.xmds`
- `.\lorenz.cmd`
- top-level regression groups run individually and passing
- rerun of a user example with numerically consistent output compared to Linux results

I would be happy to split this into smaller patches if that would make review easier.

Per the XMDS2 licensing page, I agree to license my contributions under the GPL v2 license.

Best regards,

YOUR NAME
YOUR AFFILIATION
YOUR CONTACT
