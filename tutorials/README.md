# XMDS Extended Tutorial

[English](README.md) | [Chinese (简体中文)](README-zh.md)

This tutorial is written for the current `xmds-extended` repository. It combines the upstream XMDS documentation with the native Windows workflow added in this fork.

## 1. What XMDS is

XMDS2 is a code-generation framework for solving ordinary, partial, and stochastic differential equations. You describe a simulation in an `.xmds` file, XMDS generates C++ code, compiles it, and then runs the compiled program.

Official sources:

- Overview: https://xmds.sourceforge.net/
- Installation: https://xmds.sourceforge.net/installation.html
- Worked examples: https://xmds.sourceforge.net/worked_examples.html
- XML schema reference: https://xmds.sourceforge.net/reference_schema.html

## 2. What this fork changes

The upstream XMDS documentation has strong Linux and macOS coverage. This fork adds a practical Windows-native path:

- native Windows support without MSYS or WSL
- portable installer and GitHub Release zip for Windows
- `run_xmds` launcher for compile-and-run in one command
- upgrade and uninstall flows for portable installs
- CI across Windows, Linux, and macOS

## 3. Recommended learning order

If you are new to XMDS, this order works well:

1. Install the Windows portable package.
2. Compile and run `examples/lorenz.xmds`.
3. Open the `.xmds` file and connect its XML blocks to the generated output files.
4. Read a few official worked examples.
5. Start modifying an existing example instead of writing a script from scratch.

## 4. Windows installation

The recommended Windows path is the portable installer published in GitHub Releases.

### Requirements

- Windows PowerShell
- Conda or Miniforge already installed
- a short install directory such as `D:\xmds`

### Install steps

1. Download the latest `xmds-extended-windows-portable-*.zip` from Releases.
2. Extract it to a temporary directory.
3. Open PowerShell in the extracted directory.
4. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
   ```

5. Choose an install directory.
6. Decide whether to add the install directory to `PATH`.

### Upgrade

To upgrade an existing portable installation:

1. Download the newer zip.
2. Run the newer `install_windows.ps1`.
3. Choose the same install directory as the existing installation.

### Uninstall

- If the install directory is on `PATH`:

  ```powershell
  uninstall_xmds
  ```

- Otherwise:

  ```powershell
  <InstallDir>\uninstall_xmds.cmd
  ```

## 5. First successful run

After installation, the fastest validation is the Lorenz example.

### If `run_xmds` is on PATH

```powershell
run_xmds E:\path\to\xmds-extended\examples\lorenz.xmds
```

### If you did not add the install directory to PATH

```powershell
<InstallDir>\run_xmds.cmd E:\path\to\xmds-extended\examples\lorenz.xmds
```

This single command does the following:

1. prepares the bundled runtime environment
2. runs `xmds2` on the `.xmds` file
3. generates C++ source
4. compiles the simulation
5. runs the generated `.cmd` launcher

Typical outputs include:

- `lorenz.cc`
- `lorenz.exe`
- `lorenz.cmd`
- `lorenz.h5`
- `lorenz.xsil`

## 6. What each generated file means

- `.xmds`: your XMDS model description
- `.cc`: generated C++ source
- `.exe`: compiled simulation program
- `.cmd`: Windows launcher that sets up runtime DLL paths, then starts the `.exe`
- `.xsil`: XMDS metadata and output description
- `.h5` / `.dat`: numerical output data

On Windows, you should normally run the generated `.cmd`, not the `.exe` directly.

## 7. Understanding a simple XMDS script

This repository already contains a good minimal example in [`examples/lorenz.xmds`](../examples/lorenz.xmds).

Important blocks:

- `<simulation>`: the root element
- `<name>`: simulation name and output prefix
- `<features>`: globals and optional features
- `<geometry>`: propagation and spatial dimensions
- `<vector>`: evolving variables and initial values
- `<sequence>`: integration algorithm and equations
- `<output>`: what quantities are written out

In `lorenz.xmds`:

- the propagation dimension is time `t`
- the evolving variables are `x`, `y`, and `z`
- the integrator is `ARK89`
- the output saves the sampled moments `xR`, `yR`, and `zR`

That is a good first script to read because it is small, complete, and maps clearly onto the Lorenz system.

## 8. Working from any directory

Once installed, you do not need to work inside the repository directory.

Example:

```powershell
run_xmds D:\Simulations\my_case.xmds
```

XMDS will compile inside the directory containing `my_case.xmds`, and the generated `.cc`, `.cmd`, `.exe`, and output files will appear there.

## 9. Plotting and Python helpers

If you have a Python plotting script that reads XMDS output, use the installed plotting launcher:

```powershell
run_plot D:\Simulations\plot_result.py
```

This launcher uses the packaged runtime and sets `PYTHONPATH` / plotting backend for the installed XMDS environment.

## 10. Learning from official XMDS material

The official XMDS documentation is still the best source for learning the language itself.

Recommended upstream pages:

- Official welcome page: https://xmds.sourceforge.net/
- Worked examples: https://xmds.sourceforge.net/worked_examples.html
- Installation reference: https://xmds.sourceforge.net/installation.html
- XML schema reference: https://xmds.sourceforge.net/reference_schema.html

The official worked examples are especially useful because they progress from simple systems to more advanced PDE, stochastic, FFT, MPI, and basis-transform cases.

## 11. Recommended workflow for new projects

For practical work in this fork, a good pattern is:

1. copy an existing example close to your physics problem
2. rename the file and simulation name
3. edit globals, vectors, operators, and output
4. run with `run_xmds`
5. compare results against a trusted baseline
6. add a plotting script if needed

## 12. Troubleshooting

### `run_xmds` is not recognized

Open a new terminal after installation, or call the launcher by full path:

```powershell
<InstallDir>\run_xmds.cmd C:\path\to\simulation.xmds
```

### HDF5 / FFTW / DLL errors

Prefer the generated `.cmd` launcher rather than starting the `.exe` directly.

### MPI not found

This only means MPI-based scripts are unavailable in the current environment. Single-process scripts still work.

### Installation path too long

Choose a shorter install directory. The bundled Windows toolchain is more reliable with short paths.

## 13. Repository-specific pointers

- Project overview: [`../README.md`](../README.md)
- Chinese tutorial: [`README-zh.md`](README-zh.md)
- Windows native notes: [`../docs/windows-native-guide-zh.md`](../docs/windows-native-guide-zh.md)
- Installer design: [`../docs/windows-portable-installer-design-zh.md`](../docs/windows-portable-installer-design-zh.md)
- Upgrade design: [`../docs/windows-portable-upgrade-design-zh.md`](../docs/windows-portable-upgrade-design-zh.md)

## 14. Source attribution

This tutorial is based on:

- the upstream XMDS2 documentation site
- the worked examples and example files included with XMDS
- the native Windows workflow implemented in this repository
