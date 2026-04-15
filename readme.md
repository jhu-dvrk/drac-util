# dRAC utilities

`dractest`: Manufacturing test software to test dRAC PCBA and dVRK-Si controller. Requires a [test board](https://github.com/jhu-dvrk/dvrk-si-test-board) or equivalent loopback connectors. **Do not use with robot connected.**

`dractune`: Current loop tuning tool for dRAC. **Not maintained and probably does not work.**

`dractweak`: View and control the low level states of the robot.  **Not maintained and probably does not work.**

## Linux build dependencies

```
sudo apt install libraw1394-dev libglfw3-dev libglew-dev
```

## Windows bootstrap

Use the bootstrap script below on a fresh Windows machine to install the Microsoft C++ toolchain, set up `vcpkg`, install `glfw3` and `glew`, sync submodules, and validate the repo helper.

```powershell
.\scripts\bootstrap-windows.ps1
```

By default it installs Visual Studio 2022 Community. For a lighter tool-only setup:

```powershell
.\scripts\bootstrap-windows.ps1 -VisualStudioEdition BuildTools
```

It can also persist `VCPKG_ROOT` for the current user:

```powershell
.\scripts\bootstrap-windows.ps1 -PersistVcpkgRoot
```

The Visual Studio installer may prompt for elevation and can report that a reboot is needed before the full toolchain is usable.

After bootstrap, use the helper below to enter a Visual Studio x64 shell with MSVC, CMake, and an optional `vcpkg` root added to `PATH`.

```powershell
. .\scripts\enter-windows-toolchain.ps1
cmake --list-presets
cmake --preset windows-msvc-x64
```

Running the script without dot-sourcing launches a child PowerShell that already has the toolchain activated:

```powershell
.\scripts\enter-windows-toolchain.ps1
```

The helper script looks for `vcpkg` in `VCPKG_ROOT`, `C:\dev\vcpkg`, and `C:\lib\vcpkg`. If it finds one, it also sets `CMAKE_TOOLCHAIN_FILE`.

```powershell
cmake --preset windows-msvc-x64
cmake --build --preset windows-release
```

## Windows dractest release

To stage a portable `dractest` bundle without the rest of the repo install tree:

```powershell
cmake --install build\windows-msvc-x64 --config Release --component dractest-runtime --prefix build\dractest-stage
```

To stage and zip the release in one step:

```powershell
cmake --build --preset windows-release --target dractest_package
```

That creates:

```text
build\windows-msvc-x64\release\dractest-Release-windows-x64.zip
```

GitHub Actions can generate the same Windows release zip automatically using [windows-dractest-release.yml](.github/workflows/windows-dractest-release.yml).

Manual trigger:

1. Open the repository on GitHub.
2. Open the `Actions` tab.
3. Select `Windows dractest release`.
4. Click `Run workflow`.
5. Download the `dractest-windows-x64` artifact from that workflow run.

Tagged release trigger:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

Pushing a tag matching `v*` runs the same Windows build and uploads the zip to the corresponding GitHub Release.
