[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("Community", "BuildTools")]
    [string]$VisualStudioEdition = "Community",

    [string]$VcpkgRoot = "C:\dev\vcpkg",

    [string]$VcpkgTriplet = "x64-windows",

    [switch]$PersistVcpkgRoot,

    [switch]$SkipVisualStudio,

    [switch]$SkipVcpkg,

    [switch]$SkipPackages,

    [switch]$SkipSubmodules,

    [switch]$SkipValidation,

    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "==> $Message"
}

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

    return $null
}

function Test-VsToolchainReady {
    $vsRoot = Get-VsInstallRoot
    if (-not $vsRoot) {
        return $null
    }

    $vcvarsPath = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"
    $cmakePath = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

    if ((Test-Path $vcvarsPath) -and (Test-Path $cmakePath)) {
        return [pscustomobject]@{
            InstallRoot = $vsRoot
            VcvarsPath = $vcvarsPath
            CMakePath = $cmakePath
        }
    }

    return $null
}

function Get-VsBootstrapperInfo {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Community", "BuildTools")]
        [string]$Edition
    )

    switch ($Edition) {
        "Community" {
            return @{
                Url = "https://aka.ms/vs/17/release/vs_community.exe"
                FileName = "vs_community.exe"
                DisplayName = "Visual Studio 2022 Community"
            }
        }
        "BuildTools" {
            return @{
                Url = "https://aka.ms/vs/17/release/vs_buildtools.exe"
                FileName = "vs_buildtools.exe"
                DisplayName = "Visual Studio 2022 Build Tools"
            }
        }
    }
}

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory,

        [int[]]$SuccessExitCodes = @(0)
    )

    $startInfo = @{
        FilePath = $FilePath
        ArgumentList = $ArgumentList
        Wait = $true
        PassThru = $true
    }

    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @startInfo
    if ($SuccessExitCodes -notcontains $process.ExitCode) {
        throw "Command failed with exit code $($process.ExitCode): $FilePath $($ArgumentList -join ' ')"
    }
}

function Ensure-VisualStudio {
    if ($SkipVisualStudio) {
        Write-Step "Skipping Visual Studio install because -SkipVisualStudio was provided."
        return
    }

    $toolchain = Test-VsToolchainReady
    if ($toolchain) {
        Write-Step "Found existing MSVC toolchain at '$($toolchain.InstallRoot)'."
        return
    }

    $bootstrapper = Get-VsBootstrapperInfo -Edition $VisualStudioEdition
    $bootstrapperPath = Join-Path $env:TEMP $bootstrapper.FileName

    if (-not (Test-Path $bootstrapperPath)) {
        Write-Step "Downloading $($bootstrapper.DisplayName) bootstrapper."
        if ($PSCmdlet.ShouldProcess($bootstrapper.Url, "Download $($bootstrapper.FileName)")) {
            Invoke-WebRequest -Uri $bootstrapper.Url -OutFile $bootstrapperPath
        }
    }

    $arguments = @(
        "--wait",
        "--norestart",
        "--add", "Microsoft.VisualStudio.Workload.NativeDesktop",
        "--includeRecommended"
    )
    if ($Quiet) {
        $arguments += "--quiet"
    } else {
        $arguments += "--passive"
    }

    Write-Step "Installing $($bootstrapper.DisplayName). This may prompt for elevation."
    if ($PSCmdlet.ShouldProcess($bootstrapper.DisplayName, "Install Native Desktop workload")) {
        Invoke-CheckedProcess -FilePath $bootstrapperPath -ArgumentList $arguments -SuccessExitCodes @(0, 3010)
    }

    $toolchain = Test-VsToolchainReady
    if (-not $toolchain) {
        throw "Visual Studio installation finished, but the MSVC+CMake toolchain was not detected."
    }

    Write-Step "Visual Studio toolchain is ready at '$($toolchain.InstallRoot)'."
}

function Ensure-Git {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        throw "Git is required for this bootstrap script. Install Git first, or place vcpkg at '$VcpkgRoot' before rerunning."
    }

    return $git.Source
}

function Ensure-Vcpkg {
    if ($SkipVcpkg) {
        Write-Step "Skipping vcpkg setup because -SkipVcpkg was provided."
        return
    }

    $resolvedVcpkgRoot = $VcpkgRoot
    $vcpkgExe = Join-Path $resolvedVcpkgRoot "vcpkg.exe"
    $bootstrapScript = Join-Path $resolvedVcpkgRoot "bootstrap-vcpkg.bat"

    if (-not (Test-Path $vcpkgExe)) {
        if (-not (Test-Path $resolvedVcpkgRoot)) {
            $null = Ensure-Git
            Write-Step "Cloning vcpkg into '$resolvedVcpkgRoot'."
            if ($PSCmdlet.ShouldProcess($resolvedVcpkgRoot, "Clone vcpkg repository")) {
                & git clone https://github.com/microsoft/vcpkg.git $resolvedVcpkgRoot
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to clone vcpkg."
                }
            }
        }

        if (-not (Test-Path $bootstrapScript)) {
            throw "vcpkg exists at '$resolvedVcpkgRoot', but bootstrap-vcpkg.bat was not found."
        }

        Write-Step "Bootstrapping vcpkg."
        if ($PSCmdlet.ShouldProcess($resolvedVcpkgRoot, "Bootstrap vcpkg")) {
            Push-Location $resolvedVcpkgRoot
            try {
                & $bootstrapScript -disableMetrics
                if ($LASTEXITCODE -ne 0) {
                    throw "bootstrap-vcpkg.bat failed."
                }
            }
            finally {
                Pop-Location
            }
        }
    } else {
        Write-Step "Found existing vcpkg at '$resolvedVcpkgRoot'."
    }

    if (-not (Test-Path $vcpkgExe)) {
        throw "vcpkg.exe was not found at '$resolvedVcpkgRoot' after setup."
    }

    if ($PersistVcpkgRoot) {
        Write-Step "Persisting VCPKG_ROOT for the current user."
        if ($PSCmdlet.ShouldProcess("User environment", "Set VCPKG_ROOT=$resolvedVcpkgRoot")) {
            [Environment]::SetEnvironmentVariable("VCPKG_ROOT", $resolvedVcpkgRoot, "User")
        }
    }
}

function Ensure-VcpkgPackages {
    if ($SkipPackages) {
        Write-Step "Skipping vcpkg package install because -SkipPackages was provided."
        return
    }

    $vcpkgExe = Join-Path $VcpkgRoot "vcpkg.exe"
    if (-not (Test-Path $vcpkgExe)) {
        throw "Cannot install vcpkg packages because '$vcpkgExe' does not exist."
    }

    $packages = @(
        "glfw3:$VcpkgTriplet",
        "glew:$VcpkgTriplet"
    )

    Write-Step "Installing vcpkg packages: $($packages -join ', ')."
    if ($PSCmdlet.ShouldProcess($VcpkgRoot, "Install $($packages -join ', ')")) {
        & $vcpkgExe install @packages
        if ($LASTEXITCODE -ne 0) {
            throw "vcpkg install failed."
        }
    }
}

function Ensure-Submodules {
    if ($SkipSubmodules) {
        Write-Step "Skipping submodule sync because -SkipSubmodules was provided."
        return
    }

    if (-not (Test-Path (Join-Path $script:RepoRoot ".git"))) {
        Write-Step "Skipping submodules because this checkout does not appear to be a git worktree."
        return
    }

    $null = Ensure-Git

    Write-Step "Synchronizing and initializing git submodules."
    if ($PSCmdlet.ShouldProcess($script:RepoRoot, "git submodule sync/update")) {
        Push-Location $script:RepoRoot
        try {
            & git submodule sync --recursive
            if ($LASTEXITCODE -ne 0) {
                throw "git submodule sync failed."
            }

            & git submodule update --init --recursive
            if ($LASTEXITCODE -ne 0) {
                throw "git submodule update failed."
            }
        }
        finally {
            Pop-Location
        }
    }
}

function Validate-Bootstrap {
    if ($SkipValidation) {
        Write-Step "Skipping validation because -SkipValidation was provided."
        return
    }

    $enterScript = Join-Path $PSScriptRoot "enter-windows-toolchain.ps1"
    if (-not (Test-Path $enterScript)) {
        throw "Validation failed because '$enterScript' does not exist."
    }

    Write-Step "Validating the activated Windows toolchain helper."
    if ($PSCmdlet.ShouldProcess($enterScript, "Run toolchain validation")) {
        & powershell.exe -NoLogo -ExecutionPolicy Bypass -File $enterScript -Command "cmake --list-presets"
        if ($LASTEXITCODE -ne 0) {
            throw "Toolchain validation failed."
        }
    }
}

Write-Step "Repo root: $script:RepoRoot"
Write-Step "Bootstrap target: VisualStudioEdition=$VisualStudioEdition, VcpkgRoot=$VcpkgRoot, Triplet=$VcpkgTriplet"

Ensure-VisualStudio
Ensure-Vcpkg
Ensure-VcpkgPackages
Ensure-Submodules
Validate-Bootstrap

Write-Step "Windows bootstrap finished."
Write-Host "Next step: .\scripts\enter-windows-toolchain.ps1"
