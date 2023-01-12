﻿#Requires -Version 5.0
using namespace System.Management.Automation

Function Write-InformationColorized {
    <#
        .SYNOPSIS
            Writes messages to the information stream, optionally with
            color when written to the host.
        .DESCRIPTION
            An alternative to Write-Host which will write to the information stream
            and the host (optionally in colors specified) but will honor the
            $InformationPreference of the calling context.
            In PowerShell 5.0+ Write-Host calls through to Write-Information but
            will _always_ treats $InformationPreference as 'Continue', so the caller
            cannot use other options to the preference variable as intended.

        .LINK
            https://blog.kieranties.com/2018/03/26/write-information-with-colours
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object]$MessageData,
        [ConsoleColor]$ForegroundColor = $Host.UI.RawUI.ForegroundColor, # Make sure we use the current colours by default
        [ConsoleColor]$BackgroundColor = $Host.UI.RawUI.BackgroundColor,
        [Switch]$NoNewline
    )

    $msg = [HostInformationMessage]@{
        Message         = $MessageData
        ForegroundColor = $ForegroundColor
        BackgroundColor = $BackgroundColor
        NoNewline       = $NoNewline.IsPresent
    }

    Write-Information $msg
}

function GetSQLFileContent {
    param ([string]$fileName)
    return Get-Content -Path ([System.IO.Path]::Combine($script:tcdbtools_SqlDir, $fileName)) -Raw
}

function InstallPackage {
    param (
        [System.IO.DirectoryInfo]$path,
        [string]$packageName,
        [string]$packageSourceName,
        [string]$version,
        [switch]$SkipDependencies
    )

    $packageArgs = @{
        Name = $packageName
        ProviderName = "NuGet"
        Source = $packageSourceName
    }

    if ($version) {
        $packageArgs.Add("RequiredVersion", $version)
    }

    if (-not (Test-Path $path.FullName -PathType Container)) {
        New-Item $path.FullName -ErrorAction SilentlyContinue -Force -ItemType Directory
    }

    $package = Find-Package @packageArgs
    $packagePath = "$($path.FullName)\$($package.Name).$($package.Version)"

    if (-not (Test-Path $packagePath -PathType Container)) {
        # remove any older versions of the package
        Remove-Item "$($path.FullName)\$($package.Name)*" -Recurse -Force
        Write-Verbose "Installing Package: $($packageName)"
        $package = Install-Package @packageArgs -Scope CurrentUser -Destination $path.FullName -Force -SkipDependencies:$SkipDependencies.IsPresent
    }

    return $packagePath
}

function LoadAssembly {
    param ([System.IO.FileInfo]$path)
    # list loaded assemblies:
    # [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object Location | Sort-Object -Property FullName | Select-Object -Property FullName, Location, GlobalAssemblyCache, IsFullyTrusted | Out-GridView

    # load the assembly bytes so as to not lock the file
    Write-Verbose "Loading assembly: $($path.FullName)"

    # Add-Type -Path $path.FullName
    # $bytes = [System.IO.File]::ReadAllBytes($path.FullName)
    # [System.Reflection.Assembly]::Load($bytes) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($path.FullName) | Out-Null
    # Write-Host $ass | Format-List
}

function LoadAssemblies {
    param ([string]$path)

    $tmpPath = Get-Item $path
    $dllPaths = (Get-ChildItem -Path $tmpPath.FullName -Filter "*.dll")

    foreach ($dllPath in $dllPaths) {
        LoadAssembly -path $dllPath
    }
}

