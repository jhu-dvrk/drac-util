[CmdletBinding()]
param(
    [string]$Command
)

$ErrorActionPreference = "Stop"

function Get-VsInstallRoot {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $json = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json
        if ($LASTEXITCODE -eq 0 -and $json) {
            $install = $json | ConvertFrom-Json
            if ($install -is [array]) {
                $install = $install[0]
            }
            if ($install.installationPath) {
                return $install.installationPath
            }
        }
    }

    $roots = @(
        "C:\Program Files\Microsoft Visual Studio\2022",
        "C:\Program Files\Microsoft Visual Studio\2019"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $candidate = Get-ChildItem -Path $root -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName "VC\Auxiliary\Build\vcvars64.bat") } |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw "Could not find a Visual Studio installation with vcvars64.bat."
}

function Get-VcpkgRoot {
    $candidates = @()
    if ($env:VCPKG_ROOT) {
        $candidates += $env:VCPKG_ROOT
    }
    $candidates += @(
        "C:\dev\vcpkg",
        "C:\lib\vcpkg",
        (Join-Path $script:RepoRoot "vcpkg")
    )

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }
        $vcpkgExe = Join-Path $candidate "vcpkg.exe"
        if (Test-Path $vcpkgExe) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Import-EnvironmentFromBatchFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchFile
    )

    $lines = & cmd.exe /d /c "call `"$BatchFile`" >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to activate the MSVC environment using $BatchFile."
    }

    foreach ($line in $lines) {
        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -lt 1) {
            continue
        }

        $name = $line.Substring(0, $separatorIndex)
        $value = $line.Substring($separatorIndex + 1)
        Set-Item -Path "Env:$name" -Value $value
    }
}

function Prepend-ToPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Entries
    )

    $current = @()
    if ($env:PATH) {
        $current = $env:PATH -split ";"
    }

    $newPath = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Entries + $current) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }
        if (-not (Test-Path $entry)) {
            continue
        }
        if ($newPath -notcontains $entry) {
            $newPath.Add($entry)
        }
    }

    $env:PATH = ($newPath -join ";")
}

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$currentLocation = (Get-Location).Path

$vsRoot = Get-VsInstallRoot
$vcvarsPath = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"
$cmakeDir = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"

Import-EnvironmentFromBatchFile -BatchFile $vcvarsPath

$pathEntries = @()
if (Test-Path $cmakeDir) {
    $pathEntries += $cmakeDir
}

$vcpkgRoot = Get-VcpkgRoot
if ($vcpkgRoot) {
    $pathEntries += $vcpkgRoot
    $env:VCPKG_ROOT = $vcpkgRoot

    $vcpkgToolchain = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"
    if (Test-Path $vcpkgToolchain) {
        $env:CMAKE_TOOLCHAIN_FILE = $vcpkgToolchain
    }
}

Prepend-ToPath -Entries $pathEntries

$env:DRACTWEAK_REPO_ROOT = $script:RepoRoot
$env:DRACTWEAK_WINDOWS_TOOLCHAIN = "1"

$summary = "Windows toolchain ready: MSVC from '$vsRoot'" +
    $(if ($vcpkgRoot) { ", vcpkg at '$vcpkgRoot'." } else { "." })

Write-Host $summary
Write-Host "Current directory: $currentLocation"
Write-Host "Repo root: $script:RepoRoot"

$dotSourced = $MyInvocation.InvocationName -eq "."
if ($PSBoundParameters.ContainsKey("Command")) {
    Invoke-Expression $Command
    exit $LASTEXITCODE
}

if ($dotSourced) {
    Write-Host "This shell is now configured. Try: cmake --list-presets"
    return
}

Write-Host "Launching a child PowerShell with the activated environment."
powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '$currentLocation'"
