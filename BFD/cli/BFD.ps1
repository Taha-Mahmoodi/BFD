[CmdletBinding()]
param(
    [string]$DownloadsRoot = (Join-Path $env:USERPROFILE "Downloads"),
    [string]$BaseFolderName = "BFD Fonts",
    [string]$DateFormat = "yyyy-MM-dd",
    [string[]]$Providers = @("google_fonts"),
    [ValidateSet("direct", "api", "html")]
    [string[]]$MethodOrder = @("direct", "api", "html"),
    [string]$GoogleApiKey = $env:GOOGLE_FONTS_API_KEY,
    [bool]$AutoInstallFonts = $true,
    [ValidateSet("currentuser", "allusers")]
    [string]$InstallScope = "currentuser"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\core\BFD.Engine.psm1") -Force

function Normalize-BfdProviders {
    param([Parameter(Mandatory = $false)][string[]]$Values)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        foreach ($part in ($value -split ",")) {
            $token = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                $result.Add($token)
            }
        }
    }

    if ($result.Count -eq 0) {
        $result.Add("google_fonts")
    }

    return [string[]]$result.ToArray()
}

$Providers = Normalize-BfdProviders -Values $Providers

Write-Host "[BFD] Starting run"
Write-Host "[BFD] Providers: $($Providers -join ', ')"
Write-Host "[BFD] Method order: $($MethodOrder -join ' -> ')"

$eventCallback = {
    param($eventName, $data)

    switch ($eventName) {
        "provider_started" {
            Write-Host ("[BFD] Provider {0}/{1}: {2}" -f $data.index, $data.total, $data.providerName)
            break
        }
        "provider_attempt" {
            Write-Host ("[BFD]  - Attempt {0}/{1}: {2}" -f $data.index, $data.total, $data.method)
            break
        }
        "provider_attempt_failed" {
            Write-Warning ("[BFD]  - {0} failed on {1}: {2}" -f $data.providerName, $data.method, $data.message)
            break
        }
        "provider_completed" {
            Write-Host ("[BFD] Provider done: {0}; status={1}; fonts={2}" -f $data.providerName, $data.status, $data.fontCount)
            break
        }
    }
}

$summary = Invoke-BfdRun -Providers $Providers -MethodOrder $MethodOrder -DownloadsRoot $DownloadsRoot -BaseFolderName $BaseFolderName -DateFormat $DateFormat -GoogleApiKey $GoogleApiKey -EventCallback $eventCallback

Write-Host ""
Write-Host "[BFD] Download summary"
Write-Host ("[BFD] Output: {0}" -f $summary.outputFolder)
Write-Host ("[BFD] Total fonts: {0}" -f $summary.totalFonts)
Write-Host ("[BFD] Providers success/skipped: {0}/{1}" -f $summary.successfulProviders, $summary.skippedProviders)

if ($AutoInstallFonts -and [int]$summary.totalFonts -gt 0) {
    Write-Host ("[BFD] Starting installation (scope: {0})" -f $InstallScope)

    $installCallback = {
        param($eventName, $data)
        if ($eventName -eq "install_progress") {
            Write-Host ("[BFD] Install {0}/{1}: {2}" -f $data.current, $data.total, $data.font)
        }
    }

    $installResult = Install-BfdFonts -FontsRoot ([string]$summary.outputFolder) -Scope $InstallScope -ProgressCallback $installCallback
    Write-Host ("[BFD] Installation done. Installed={0}; Failed={1}" -f $installResult.succeeded, $installResult.failed)

    if ([int]$installResult.failed -gt 0) {
        throw "Installation finished with failures."
    }
}

Write-Host "[BFD] Completed."
