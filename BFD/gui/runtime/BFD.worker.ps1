[CmdletBinding()]
param(
    [string]$DownloadsRoot = (Join-Path $env:USERPROFILE "Downloads"),
    [string]$BaseFolderName = "BFD Fonts",
    [string]$DateFormat = "yyyy-MM-dd",
    [string[]]$Providers = @("google_fonts"),
    [ValidateSet("direct", "api", "html")]
    [string[]]$MethodOrder = @("direct", "api", "html"),
    [string]$GoogleApiKey = $env:GOOGLE_FONTS_API_KEY,
    [object]$AutoInstallFonts = $true,
    [ValidateSet("currentuser", "allusers")]
    [string]$InstallScope = "currentuser",
    [string]$ControlFilePath = "",
    [switch]$EmitGuiEvents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$moduleCandidates = @(
    (Join-Path $PSScriptRoot "..\..\core\BFD.Engine.psm1"),
    (Join-Path $PSScriptRoot "..\core\BFD.Engine.psm1"),
    (Join-Path $PSScriptRoot "BFD.Engine.psm1")
)

$engineModule = $moduleCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $engineModule) {
    throw "BFD.Engine.psm1 not found near worker runtime."
}
Import-Module $engineModule -Force

$script:GuiPrefix = "__FX_GUI_EVENT__"
$script:OverallPercent = 0
$script:ProviderCount = [Math]::Max(1, $Providers.Count)
$script:OutputFolder = ""
$script:CurrentProviderIndex = 1
$script:CurrentProviderName = ""

function Convert-ToBfdBoolean {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Value,
        [Parameter(Mandatory = $false)][bool]$Default = $true
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Default
    }

    switch ($text.Trim().ToLowerInvariant()) {
        "true" { return $true }
        "1" { return $true }
        "yes" { return $true }
        "y" { return $true }
        "on" { return $true }
        "false" { return $false }
        "0" { return $false }
        "no" { return $false }
        "n" { return $false }
        "off" { return $false }
    }

    return $Default
}

function Write-GuiEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $false)][hashtable]$Data = @{}
    )

    if (-not $EmitGuiEvents) {
        return
    }

    $payload = @{ timestamp = (Get-Date).ToString("o"); event = $Event }
    foreach ($entry in $Data.GetEnumerator()) {
        $payload[$entry.Key] = $entry.Value
    }

    $json = $payload | ConvertTo-Json -Compress -Depth 8
    [Console]::Out.WriteLine($script:GuiPrefix + $json)
}

function Set-OverallProgress {
    param([Parameter(Mandatory = $true)][double]$Percent, [Parameter(Mandatory = $true)][string]$Message)

    $next = [Math]::Round([Math]::Min(100, [Math]::Max(0, $Percent)), 2)
    if ($next -lt $script:OverallPercent) {
        $next = $script:OverallPercent
    }

    $script:OverallPercent = $next
    Write-GuiEvent -Event "overall_progress" -Data @{ percent = $next; message = $Message }
}

function Write-Status {
    param([Parameter(Mandatory = $true)][string]$Message, [ValidateSet("info", "warning", "error")][string]$Level = "info")

    Write-GuiEvent -Event "status" -Data @{ level = $Level; message = $Message }
    if ($Level -eq "error") {
        Write-Error $Message
    }
    elseif ($Level -eq "warning") {
        Write-Warning $Message
    }
    else {
        Write-Host "[INFO] $Message"
    }
}

$eventCallback = {
    param($eventName, $data)

    switch ($eventName) {
        "provider_started" {
            $script:CurrentProviderIndex = [Math]::Max(1, [int]$data.index)
            $script:CurrentProviderName = [string]$data.providerName
            $provider = [string]$data.providerName
            Write-Status -Message ("Provider started ({0}/{1}): {2}" -f $data.index, $data.total, $provider)
            Write-GuiEvent -Event "provider_started" -Data @{ provider = [string]$data.provider; providerName = $provider; index = [int]$data.index; total = [int]$data.total }
            break
        }
        "provider_attempt" {
            $provider = [string]$data.providerName
            $method = [string]$data.method
            Write-Status -Message ("Trying {0} ({1}/{2}) on {3}" -f $method, $data.index, $data.total, $provider)
            Write-GuiEvent -Event "provider_attempt" -Data @{ provider = [string]$data.provider; providerName = $provider; method = $method; index = [int]$data.index; total = [int]$data.total }
            break
        }
        "provider_attempt_failed" {
            Write-Status -Message ("{0} ({1}) failed: {2}" -f $data.providerName, $data.method, $data.message) -Level "warning"
            Write-GuiEvent -Event "provider_attempt_failed" -Data @{ provider = [string]$data.provider; providerName = [string]$data.providerName; method = [string]$data.method; message = [string]$data.message }
            break
        }
        "stage_progress" {
            $stage = [string]$data.stage
            $providerId = [string]$data.provider
            $percent = [double]$data.percent
            $message = [string]$data.message
            Write-GuiEvent -Event "stage_progress" -Data @{ provider = $providerId; stage = $stage; percent = $percent; message = $message }

            $providerStep = 80.0 / $script:ProviderCount
            $overallPercent = (($script:CurrentProviderIndex - 1) * $providerStep) + (($percent / 100.0) * $providerStep)
            $progressMessage = if ([string]::IsNullOrWhiteSpace($script:CurrentProviderName)) { $message } else { "$($script:CurrentProviderName): $message" }
            Set-OverallProgress -Percent $overallPercent -Message $progressMessage
            break
        }
        "provider_completed" {
            $status = [string]$data.status
            $provider = [string]$data.providerName
            $fontCount = [int]$data.fontCount
            Write-Status -Message ("Provider completed: {0} [{1}] fonts={2}" -f $provider, $status, $fontCount)
            Write-GuiEvent -Event "provider_completed" -Data @{ provider = [string]$data.provider; providerName = $provider; status = $status; methodUsed = [string]$data.methodUsed; fontCount = $fontCount; outputFolder = [string]$data.outputFolder }

            $providerStep = 80.0 / $script:ProviderCount
            $overallPercent = [Math]::Min(80, $script:CurrentProviderIndex * $providerStep)
            Set-OverallProgress -Percent $overallPercent -Message ("Completed provider: {0}" -f $provider)
            break
        }
    }
}

try {
    Set-OverallProgress -Percent 1 -Message "Initializing BFD worker"
    Write-Status -Message "BFD worker initialized."
    $AutoInstallFonts = Convert-ToBfdBoolean -Value $AutoInstallFonts -Default $true

    $summary = Invoke-BfdRun -Providers $Providers -MethodOrder $MethodOrder -DownloadsRoot $DownloadsRoot -BaseFolderName $BaseFolderName -DateFormat $DateFormat -GoogleApiKey $GoogleApiKey -EventCallback $eventCallback -StopSignalPath $ControlFilePath
    $script:OutputFolder = [string]$summary.outputFolder

    Set-OverallProgress -Percent 80 -Message "Download phase completed"
    Write-GuiEvent -Event "download_completed" -Data @{ outputFolder = $summary.outputFolder; totalFonts = $summary.totalFonts; successfulProviders = $summary.successfulProviders }

    if ($AutoInstallFonts -and [int]$summary.totalFonts -gt 0) {
        Write-GuiEvent -Event "phase_changed" -Data @{ phase = "installation" }
        Write-Status -Message "Starting installation phase."

        $installCallback = {
            param($eventName, $data)
            if ($eventName -eq "install_progress") {
                Write-GuiEvent -Event "install_progress" -Data @{ percent = [double]$data.percent; current = [int]$data.current; total = [int]$data.total; font = [string]$data.font }
                Set-OverallProgress -Percent (80 + (20 * ([double]$data.percent / 100.0))) -Message "Installing fonts"
            }
        }

        $installResult = Install-BfdFonts -FontsRoot ([string]$summary.outputFolder) -Scope $InstallScope -ProgressCallback $installCallback -StopSignalPath $ControlFilePath
        if ([int]$installResult.failed -gt 0) {
            throw "Installation completed with failures: $($installResult.failed)"
        }

        Write-GuiEvent -Event "install_completed" -Data @{ message = "Installation completed successfully."; installed = [int]$installResult.succeeded; total = [int]$installResult.total }
    }

    Set-OverallProgress -Percent 100 -Message "BFD run completed"
    Write-GuiEvent -Event "completed" -Data @{ outcome = "success"; outputFolder = $summary.outputFolder; totalFonts = [int]$summary.totalFonts; successfulProviders = [int]$summary.successfulProviders; skippedProviders = [int]$summary.skippedProviders }
    exit 0
}
catch [System.OperationCanceledException] {
    Write-Status -Message "Run stopped by user." -Level "warning"
    Write-GuiEvent -Event "completed" -Data @{ outcome = "stopped"; message = "Stopped by user."; outputFolder = $script:OutputFolder }
    exit 2
}
catch {
    $message = $_.Exception.Message
    Write-Status -Message $message -Level "warning"
    Write-GuiEvent -Event "failed" -Data @{ message = $message; outputFolder = $script:OutputFolder }
    exit 1
}
