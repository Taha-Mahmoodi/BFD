
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Enable-BfdTls {
    try {
        $p = [System.Net.SecurityProtocolType]::Tls12
        if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains "Tls13") {
            $p = $p -bor [System.Net.SecurityProtocolType]::Tls13
        }
        [System.Net.ServicePointManager]::SecurityProtocol = $p
    }
    catch {
        # Best effort.
    }
}

function Invoke-BfdEvent {
    param(
        [Parameter(Mandatory = $false)][scriptblock]$Callback,
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $false)][hashtable]$Data = @{}
    )

    if ($null -ne $Callback) {
        & $Callback $Event $Data
    }
}

function Ensure-BfdDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-BfdProviderRegistry {
    return @{
        google_fonts = [pscustomobject]@{ id = "google_fonts"; displayName = "Google Fonts"; homeUrl = "https://fonts.google.com/"; direct = "https://github.com/google/fonts/archive/refs/heads/main.zip"; apiKind = "google" }
        font_hub = [pscustomobject]@{ id = "font_hub"; displayName = "Font Hub"; homeUrl = "https://fontshub.pro/"; direct = ""; apiKind = "" }
        dafont = [pscustomobject]@{ id = "dafont"; displayName = "DaFont"; homeUrl = "https://www.dafont.com/"; direct = ""; apiKind = "" }
        font_share = [pscustomobject]@{ id = "font_share"; displayName = "Font Share"; homeUrl = "https://www.fontshare.com/"; direct = ""; apiKind = "fontshare" }
        open_foundry = [pscustomobject]@{ id = "open_foundry"; displayName = "Open Foundry"; homeUrl = "https://open-foundry.com/"; direct = ""; apiKind = "" }
        befonts = [pscustomobject]@{ id = "befonts"; displayName = "Befonts"; homeUrl = "https://befonts.com/"; direct = ""; apiKind = "" }
    }
}

function Get-BfdDefaultProviders {
    return @("google_fonts")
}

function Resolve-BfdProviders {
    param(
        [Parameter(Mandatory = $true)][string[]]$Providers,
        [Parameter(Mandatory = $true)][hashtable]$Registry
    )

    $result = New-Object "System.Collections.Generic.List[object]"
    $seen = @{}
    foreach ($raw in $Providers) {
        $id = [string]$raw
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $id = $id.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_")
        if ($seen.ContainsKey($id)) { continue }
        if (-not $Registry.ContainsKey($id)) {
            throw "Unknown provider '$raw'. Supported: $($Registry.Keys -join ', ')"
        }
        $seen[$id] = $true
        $result.Add($Registry[$id]) | Out-Null
    }

    if ($result.Count -eq 0) {
        foreach ($id in (Get-BfdDefaultProviders)) {
            $result.Add($Registry[$id]) | Out-Null
        }
    }

    return ,$result.ToArray()
}

function Test-BfdStopRequested {
    param([Parameter(Mandatory = $false)][string]$StopSignalPath)
    return (-not [string]::IsNullOrWhiteSpace($StopSignalPath)) -and (Test-Path -LiteralPath $StopSignalPath)
}

function Assert-BfdNotStopped {
    param([Parameter(Mandatory = $false)][string]$StopSignalPath)
    if (Test-BfdStopRequested -StopSignalPath $StopSignalPath) {
        throw [System.OperationCanceledException]::new("Stop requested.")
    }
}

function Get-BfdUniqueDatedOutputFolder {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$DateFormat
    )

    Ensure-BfdDirectory -Path $RootPath
    $base = Get-Date -Format $DateFormat
    $candidate = Join-Path $RootPath $base
    if (-not (Test-Path -LiteralPath $candidate)) {
        Ensure-BfdDirectory -Path $candidate
        return $candidate
    }

    $n = 2
    while ($true) {
        $candidate = Join-Path $RootPath ("{0}-{1}" -f $base, $n)
        if (-not (Test-Path -LiteralPath $candidate)) {
            Ensure-BfdDirectory -Path $candidate
            return $candidate
        }
        $n++
    }
}

function Get-BfdFontFiles {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in @(".ttf", ".otf") })
}

function Copy-BfdFontFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Ensure-BfdDirectory -Path $Destination
    $files = Get-BfdFontFiles -Path $Source
    $copied = 0
    foreach ($file in $files) {
        $relative = $file.FullName.Substring((Resolve-Path -LiteralPath $Source).Path.Length).TrimStart("\\")
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        $target = Join-Path $Destination $relative
        Ensure-BfdDirectory -Path (Split-Path -Parent $target)
        if (Test-Path -LiteralPath $target) {
            $dir = Split-Path -Parent $target
            $base = [System.IO.Path]::GetFileNameWithoutExtension($target)
            $ext = [System.IO.Path]::GetExtension($target)
            $i = 2
            while (Test-Path -LiteralPath $target) {
                $target = Join-Path $dir ("{0}-{1}{2}" -f $base, $i, $ext)
                $i++
            }
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied++
    }

    return $copied
}

function Get-BfdSafeFileName {
    param(
        [Parameter(Mandatory = $false)][string]$Value,
        [Parameter(Mandatory = $false)][string]$Fallback = "asset"
    )

    $name = [string]$Value
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $Fallback
    }

    $name = ($name -replace '[<>:"/\\|?*]', "_").Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $Fallback
    }

    return $name
}

function Get-BfdUniqueFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    Ensure-BfdDirectory -Path $Directory
    $safeName = Get-BfdSafeFileName -Value $FileName -Fallback "asset.bin"
    $target = Join-Path $Directory $safeName
    if (-not (Test-Path -LiteralPath $target)) {
        return $target
    }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
    $ext = [System.IO.Path]::GetExtension($safeName)
    $n = 2
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $Directory ("{0}-{1}{2}" -f $base, $n, $ext)
        $n++
    }

    return $target
}

function Resolve-BfdAbsoluteUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $false)][string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $value = $Candidate.Trim()
    if ($value.StartsWith("//")) {
        return ("https:{0}" -f $value)
    }

    try {
        $baseUri = [uri]$BaseUrl
        return ([uri]::new($baseUri, $value)).AbsoluteUri
    }
    catch {
        return $null
    }
}

function Get-BfdHtmlLinks {
    param(
        [Parameter(Mandatory = $true)][string]$Html,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [Parameter(Mandatory = $false)][int]$Limit = 0
    )

    $results = New-Object "System.Collections.Generic.List[string]"
    $seen = @{}
    foreach ($pattern in $Patterns) {
        foreach ($match in [regex]::Matches([string]$Html, $pattern)) {
            $candidate = $null
            if ($match.Groups["u"] -and $match.Groups["u"].Success) {
                $candidate = $match.Groups["u"].Value
            }
            elseif ($match.Groups.Count -gt 1) {
                $candidate = $match.Groups[1].Value
            }
            else {
                $candidate = $match.Value
            }

            $absolute = Resolve-BfdAbsoluteUrl -BaseUrl $BaseUrl -Candidate $candidate
            if ([string]::IsNullOrWhiteSpace($absolute)) { continue }
            if ($seen.ContainsKey($absolute)) { continue }

            $seen[$absolute] = $true
            $results.Add($absolute) | Out-Null
            if ($Limit -gt 0 -and $results.Count -ge $Limit) {
                return ,$results.ToArray()
            }
        }
    }

    return ,$results.ToArray()
}

function Test-BfdZipArchive {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            if ($stream.Length -lt 4) { return $false }
            $bytes = New-Object byte[] 4
            [void]$stream.Read($bytes, 0, 4)
            return ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B -and ($bytes[2] -in @(0x03, 0x05, 0x07)) -and ($bytes[3] -in @(0x04, 0x06, 0x08)))
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $false
    }
}

function Import-BfdDownloadedAsset {
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][string]$SourceUrl = "",
        [Parameter(Mandatory = $false)][string]$ContentType = "",
        [Parameter(Mandatory = $false)][string]$ContentDisposition = ""
    )

    if (-not (Test-Path -LiteralPath $LocalPath)) {
        return [pscustomobject]@{ fontCount = 0; usedZip = $false }
    }

    $effectivePath = $LocalPath
    $ext = [System.IO.Path]::GetExtension($effectivePath).ToLowerInvariant()
    $fromDisposition = ""

    if (-not [string]::IsNullOrWhiteSpace($ContentDisposition) -and $ContentDisposition -match '(?i)filename\*?=(?<f>[^;]+)') {
        $fromDisposition = [string]$matches["f"]
        $fromDisposition = $fromDisposition.Trim().Trim('"', "'")
        $fromDisposition = [System.IO.Path]::GetExtension($fromDisposition).ToLowerInvariant()
    }

    if ($ext -notin @(".zip", ".ttf", ".otf")) {
        if ($fromDisposition -in @(".zip", ".ttf", ".otf")) {
            $target = "$effectivePath$fromDisposition"
            Move-Item -LiteralPath $effectivePath -Destination $target -Force
            $effectivePath = $target
            $ext = $fromDisposition
        }
        elseif ([string]$SourceUrl -match '\.(ttf|otf|zip)(\?|$)') {
            $extFromUrl = "." + $matches[1].ToLowerInvariant()
            $target = "$effectivePath$extFromUrl"
            Move-Item -LiteralPath $effectivePath -Destination $target -Force
            $effectivePath = $target
            $ext = $extFromUrl
        }
        elseif (([string]$ContentType).ToLowerInvariant() -match "zip" -or (Test-BfdZipArchive -Path $effectivePath)) {
            $target = "$effectivePath.zip"
            Move-Item -LiteralPath $effectivePath -Destination $target -Force
            $effectivePath = $target
            $ext = ".zip"
        }
    }

    if ($ext -in @(".ttf", ".otf")) {
        Ensure-BfdDirectory -Path $ProviderOutput
        $target = Get-BfdUniqueFilePath -Directory $ProviderOutput -FileName ([System.IO.Path]::GetFileName($effectivePath))
        Copy-Item -LiteralPath $effectivePath -Destination $target -Force
        return [pscustomobject]@{ fontCount = 1; usedZip = $false }
    }

    if ($ext -eq ".zip") {
        $extractRoot = Join-Path $TempRoot ("extract-" + [guid]::NewGuid().ToString("N"))
        Ensure-BfdDirectory -Path $extractRoot
        Expand-Archive -LiteralPath $effectivePath -DestinationPath $extractRoot -Force
        $copied = Copy-BfdFontFiles -Source $extractRoot -Destination $ProviderOutput
        return [pscustomobject]@{ fontCount = $copied; usedZip = $true }
    }

    return [pscustomobject]@{ fontCount = 0; usedZip = $false }
}

function Invoke-BfdDownloadUrlBatch {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string[]]$Urls,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath,
        [Parameter(Mandatory = $false)][string]$Label = "assets"
    )

    if ($Urls.Count -eq 0) { return 0 }

    Ensure-BfdDirectory -Path $TempRoot
    Ensure-BfdDirectory -Path $ProviderOutput

    $downloaded = 0
    $zipExtractions = 0
    for ($i = 0; $i -lt $Urls.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $url = [string]$Urls[$i]

        $name = ""
        try {
            $uriObj = [uri]$url
            $name = [System.IO.Path]::GetFileName($uriObj.AbsolutePath)
        }
        catch {
            $name = ""
        }

        if ([string]::IsNullOrWhiteSpace($name)) {
            if ($url -match '(?i)[?&]f=(?<slug>[a-z0-9._-]+)') {
                $name = "{0}.zip" -f (Get-BfdSafeFileName -Value $matches["slug"] -Fallback ("asset-{0}" -f ($i + 1)))
            }
            else {
                $name = "asset-{0}.bin" -f ($i + 1)
            }
        }

        $localPath = Get-BfdUniqueFilePath -Directory $TempRoot -FileName $name
        $response = Invoke-WebRequest -Uri $url -OutFile $localPath -TimeoutSec 180 -PassThru
        $contentType = [string]$response.Headers["Content-Type"]
        $contentDisposition = [string]$response.Headers["Content-Disposition"]

        $import = Import-BfdDownloadedAsset -LocalPath $localPath -ProviderOutput $ProviderOutput -TempRoot $TempRoot -SourceUrl $url -ContentType $contentType -ContentDisposition $contentDisposition
        $downloaded += [int]$import.fontCount
        if ([bool]$import.usedZip) { $zipExtractions++ }

        $percent = [math]::Round((100.0 * ($i + 1)) / $Urls.Count, 2)
        Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "download"; percent = $percent; message = "Processed $($i + 1) / $($Urls.Count) $Label items" }
        if ([bool]$import.usedZip) {
            Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "extract"; percent = $percent; message = "Extracted $zipExtractions archive(s)" }
        }
    }

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "extract"; percent = 100; message = "Extraction stage completed" }
    return $downloaded
}
function Invoke-BfdDirectMethod {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$Provider.direct)) {
        throw "No direct source configured."
    }

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 10; message = "Preparing direct source" }
    $count = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls @([string]$Provider.direct) -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "direct"
    if ($count -le 0) {
        throw "Direct source contained no .ttf/.otf files."
    }

    return $count
}

function Invoke-BfdGoogleApiMethod {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$GoogleApiKey,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    if ([string]::IsNullOrWhiteSpace($GoogleApiKey)) {
        throw "Google API key missing."
    }

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 20; message = "Fetching Google API metadata" }
    Assert-BfdNotStopped -StopSignalPath $StopSignalPath

    $uri = "https://www.googleapis.com/webfonts/v1/webfonts?key={0}" -f [uri]::EscapeDataString($GoogleApiKey)
    $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 180
    if (-not $response.items) {
        throw "Google API returned no families."
    }

    $queue = New-Object "System.Collections.Generic.List[object]"
    foreach ($family in $response.items) {
        if (-not $family.files) { continue }
        $familyName = Get-BfdSafeFileName -Value ([string]$family.family) -Fallback "Unknown"
        foreach ($variant in $family.files.PSObject.Properties) {
            $url = [string]$variant.Value
            if ([string]::IsNullOrWhiteSpace($url)) { continue }
            if ($url.StartsWith("http://")) { $url = "https://{0}" -f $url.Substring(7) }
            if ($url -notmatch "\.(ttf|otf)(\?|$)") { continue }
            $variantName = Get-BfdSafeFileName -Value ([string]$variant.Name) -Fallback "regular"
            $queue.Add([pscustomobject]@{ family = $familyName; variant = $variantName; url = $url }) | Out-Null
        }
    }

    if ($queue.Count -eq 0) {
        throw "Google API returned zero downloadable fonts."
    }

    $downloaded = 0
    for ($i = 0; $i -lt $queue.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $item = $queue[$i]
        $familyDir = Join-Path $ProviderOutput $item.family
        Ensure-BfdDirectory -Path $familyDir
        $ext = if ([string]$item.url -match "\.otf(\?|$)") { ".otf" } else { ".ttf" }
        $target = Get-BfdUniqueFilePath -Directory $familyDir -FileName ("{0}{1}" -f $item.variant, $ext)
        Invoke-WebRequest -Uri $item.url -OutFile $target -TimeoutSec 120
        $downloaded++
        $percent = [math]::Round((100.0 * $downloaded) / $queue.Count, 2)
        Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "download"; percent = $percent; message = "Downloaded $downloaded / $($queue.Count) Google API fonts" }
    }

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "extract"; percent = 100; message = "No archive extraction required" }
    return $downloaded
}

function Invoke-BfdFontShareApiMethod {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 20; message = "Fetching Fontshare API metadata" }
    Assert-BfdNotStopped -StopSignalPath $StopSignalPath

    $response = Invoke-RestMethod -Uri "https://api.fontshare.com/v2/fonts" -Method Get -TimeoutSec 180
    $fonts = @($response.fonts)
    if ($fonts.Count -eq 0) {
        throw "Fontshare API returned no families."
    }

    $urls = New-Object "System.Collections.Generic.List[string]"
    $seen = @{}
    foreach ($font in $fonts) {
        $slug = [string]$font.slug
        if ([string]::IsNullOrWhiteSpace($slug)) { continue }
        if ($seen.ContainsKey($slug)) { continue }
        $seen[$slug] = $true
        $encoded = [uri]::EscapeDataString($slug)
        $urls.Add("https://api.fontshare.com/v2/fonts/download/kit?f[]=$encoded") | Out-Null
    }

    if ($urls.Count -eq 0) {
        throw "Fontshare API did not expose downloadable family slugs."
    }

    $count = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls $urls.ToArray() -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "Fontshare kit"
    if ($count -le 0) {
        throw "Fontshare API produced no .ttf/.otf files."
    }

    return $count
}

function Invoke-BfdHtmlMethod_Generic {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 15; message = "Scraping provider homepage" }
    Assert-BfdNotStopped -StopSignalPath $StopSignalPath

    $home = Invoke-WebRequest -Uri ([string]$Provider.homeUrl) -UseBasicParsing -TimeoutSec 120
    if ([string]::IsNullOrWhiteSpace([string]$home.Content)) {
        throw "Provider HTML is empty."
    }

    $urls = Get-BfdHtmlLinks -Html ([string]$home.Content) -BaseUrl ([string]$Provider.homeUrl) -Patterns @(
        '(?i)(?:href|src)=["''](?<u>[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']'
    ) -Limit 80
    if ($urls.Count -eq 0) {
        throw "No downloadable links found in HTML."
    }

    $downloaded = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls $urls -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "HTML"

    if ($downloaded -le 0) {
        throw "HTML method produced no .ttf/.otf fonts."
    }

    return $downloaded
}

function Invoke-BfdHtmlMethod_FontHub {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 10; message = "Loading Font Hub index pages" }
    $home = Invoke-WebRequest -Uri ([string]$Provider.homeUrl) -UseBasicParsing -TimeoutSec 120
    $fontPages = Get-BfdHtmlLinks -Html ([string]$home.Content) -BaseUrl ([string]$Provider.homeUrl) -Patterns @(
        '(?i)href=["''](?<u>/font/[^"'']+-download)["'']',
        '(?i)href=["''](?<u>https?://(?:www\.)?fontshub\.pro/font/[^"'']+-download)["'']'
    ) -Limit 25
    if ($fontPages.Count -eq 0) {
        throw "Font Hub pages were not discovered."
    }

    $assetUrls = New-Object "System.Collections.Generic.List[string]"
    $seenAsset = @{}
    $downloadPages = New-Object "System.Collections.Generic.List[string]"
    $seenDownloadPages = @{}

    for ($i = 0; $i -lt $fontPages.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $fontPageUrl = [string]$fontPages[$i]
        $fetchPercent = [math]::Round((100.0 * ($i + 1)) / $fontPages.Count, 2)
        Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = $fetchPercent; message = "Scanning Font Hub page $($i + 1) / $($fontPages.Count)" }

        $page = Invoke-WebRequest -Uri $fontPageUrl -UseBasicParsing -TimeoutSec 120
        $content = [string]$page.Content
        $downloadPageCandidates = Get-BfdHtmlLinks -Html $content -BaseUrl $fontPageUrl -Patterns @(
            '(?i)href=["''](?<u>/font/download-full/\d+[^"'']*)["'']',
            '(?i)href=["''](?<u>https?://(?:www\.)?fontshub\.pro/font/download-full/\d+[^"'']*)["'']'
        ) -Limit 10
        foreach ($candidate in $downloadPageCandidates) {
            if ($seenDownloadPages.ContainsKey($candidate)) { continue }
            $seenDownloadPages[$candidate] = $true
            $downloadPages.Add($candidate) | Out-Null
        }

        $directAssetCandidates = Get-BfdHtmlLinks -Html $content -BaseUrl $fontPageUrl -Patterns @(
            '(?i)(?:href|src)=["''](?<u>/f-files/[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']',
            '(?i)(?:href|src)=["''](?<u>[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']'
        ) -Limit 20
        foreach ($candidate in $directAssetCandidates) {
            if ($seenAsset.ContainsKey($candidate)) { continue }
            $seenAsset[$candidate] = $true
            $assetUrls.Add($candidate) | Out-Null
        }
    }

    for ($i = 0; $i -lt $downloadPages.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $downloadPageUrl = [string]$downloadPages[$i]
        $page = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing -TimeoutSec 120
        $assets = Get-BfdHtmlLinks -Html ([string]$page.Content) -BaseUrl $downloadPageUrl -Patterns @(
            '(?i)(?:href|src)=["''](?<u>/f-files/[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']',
            '(?i)(?:href|src)=["''](?<u>[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']'
        ) -Limit 20
        foreach ($asset in $assets) {
            if ($seenAsset.ContainsKey($asset)) { continue }
            $seenAsset[$asset] = $true
            $assetUrls.Add($asset) | Out-Null
        }
    }

    if ($assetUrls.Count -eq 0) {
        throw "Font Hub HTML flow produced no downloadable assets."
    }

    $count = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls $assetUrls.ToArray() -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "Font Hub"
    if ($count -le 0) {
        throw "Font Hub produced no .ttf/.otf files."
    }

    return $count
}

function Invoke-BfdHtmlMethod_DaFont {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 15; message = "Loading DaFont index" }
    $home = Invoke-WebRequest -Uri ([string]$Provider.homeUrl) -UseBasicParsing -TimeoutSec 120
    $content = [string]$home.Content

    $urls = New-Object "System.Collections.Generic.List[string]"
    $seen = @{}

    foreach ($match in [regex]::Matches($content, '(?i)(?<u>(?:https?:)?//dl\.dafont\.com/dl/\?f=[a-z0-9._-]+(?:&[^"'']*)?)')) {
        $raw = [string]$match.Groups["u"].Value
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $absolute = if ($raw.StartsWith("//")) { "https:$raw" } else { $raw }
        if ($seen.ContainsKey($absolute)) { continue }
        $seen[$absolute] = $true
        $urls.Add($absolute) | Out-Null
        if ($urls.Count -ge 120) { break }
    }

    if ($urls.Count -lt 120) {
        foreach ($match in [regex]::Matches($content, '(?i)href=["''](?<u>/dl/\?f=[^"'']+)["'']')) {
            $absolute = Resolve-BfdAbsoluteUrl -BaseUrl ([string]$Provider.homeUrl) -Candidate ([string]$match.Groups["u"].Value)
            if ([string]::IsNullOrWhiteSpace($absolute)) { continue }
            if ($seen.ContainsKey($absolute)) { continue }
            $seen[$absolute] = $true
            $urls.Add($absolute) | Out-Null
            if ($urls.Count -ge 120) { break }
        }
    }

    if ($urls.Count -eq 0) {
        throw "DaFont HTML flow found no download links."
    }

    $count = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls $urls.ToArray() -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "DaFont"
    if ($count -le 0) {
        throw "DaFont produced no .ttf/.otf files."
    }

    return $count
}

function Invoke-BfdHtmlMethod_BeFonts {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 10; message = "Loading Befonts index pages" }
    $home = Invoke-WebRequest -Uri ([string]$Provider.homeUrl) -UseBasicParsing -TimeoutSec 120
    $postLinks = Get-BfdHtmlLinks -Html ([string]$home.Content) -BaseUrl ([string]$Provider.homeUrl) -Patterns @(
        '(?i)href=["''](?<u>https?://(?:www\.)?befonts\.com/[^"'']+\.html)["'']',
        '(?i)href=["''](?<u>/[^"'']+\.html)["'']'
    ) -Limit 35
    if ($postLinks.Count -eq 0) {
        throw "Befonts post pages were not discovered."
    }

    $assetUrls = New-Object "System.Collections.Generic.List[string]"
    $seenAsset = @{}
    $downfileUrls = New-Object "System.Collections.Generic.List[string]"
    $seenDownfile = @{}

    for ($i = 0; $i -lt $postLinks.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $postUrl = [string]$postLinks[$i]
        $percent = [math]::Round((100.0 * ($i + 1)) / $postLinks.Count, 2)
        Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = $percent; message = "Scanning Befonts page $($i + 1) / $($postLinks.Count)" }

        $post = Invoke-WebRequest -Uri $postUrl -UseBasicParsing -TimeoutSec 120
        $postContent = [string]$post.Content

        $directAssets = Get-BfdHtmlLinks -Html $postContent -BaseUrl $postUrl -Patterns @(
            '(?i)(?:href|src)=["''](?<u>[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']'
        ) -Limit 20
        foreach ($asset in $directAssets) {
            if ($seenAsset.ContainsKey($asset)) { continue }
            $seenAsset[$asset] = $true
            $assetUrls.Add($asset) | Out-Null
        }

        $downLinks = Get-BfdHtmlLinks -Html $postContent -BaseUrl $postUrl -Patterns @(
            '(?i)href=["''](?<u>[^"'']*?/downfile/[^"'']+)["'']'
        ) -Limit 10
        foreach ($down in $downLinks) {
            if ($seenDownfile.ContainsKey($down)) { continue }
            $seenDownfile[$down] = $true
            $downfileUrls.Add($down) | Out-Null
        }
    }

    for ($i = 0; $i -lt $downfileUrls.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $downUrl = [string]$downfileUrls[$i]
        $downPage = Invoke-WebRequest -Uri $downUrl -UseBasicParsing -TimeoutSec 120
        $downAssets = Get-BfdHtmlLinks -Html ([string]$downPage.Content) -BaseUrl $downUrl -Patterns @(
            '(?i)(?:href|src)=["''](?<u>[^"'']+\.(?:zip|ttf|otf)(?:\?[^"'']*)?)["'']',
            '(?i)href=["''](?<u>[^"'']*?/downfile/[^"'']+\?regen=1)["'']'
        ) -Limit 20
        foreach ($asset in $downAssets) {
            if ($seenAsset.ContainsKey($asset)) { continue }
            $seenAsset[$asset] = $true
            $assetUrls.Add($asset) | Out-Null
        }
    }

    if ($assetUrls.Count -eq 0) {
        throw "Befonts HTML flow produced no downloadable assets."
    }

    $count = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls $assetUrls.ToArray() -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "Befonts"
    if ($count -le 0) {
        throw "Befonts produced no .ttf/.otf files."
    }

    return $count
}

function Invoke-BfdHtmlMethod_OpenFoundry {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = 10; message = "Loading Open Foundry index" }
    $home = Invoke-WebRequest -Uri ([string]$Provider.homeUrl) -UseBasicParsing -TimeoutSec 120
    $stylesheets = Get-BfdHtmlLinks -Html ([string]$home.Content) -BaseUrl ([string]$Provider.homeUrl) -Patterns @(
        '(?i)(?:href|src)=["''](?<u>https?://fonts\.open-foundry\.com/[^"'']+/stylesheet\.css)["'']'
    ) -Limit 80

    $assetUrls = New-Object "System.Collections.Generic.List[string]"
    $seen = @{}
    for ($i = 0; $i -lt $stylesheets.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $cssUrl = [string]$stylesheets[$i]
        $percent = [math]::Round((100.0 * ($i + 1)) / [math]::Max(1, $stylesheets.Count), 2)
        Invoke-BfdEvent -Callback $EventCallback -Event "stage_progress" -Data @{ provider = $Provider.id; stage = "fetch"; percent = $percent; message = "Scanning Open Foundry stylesheet $($i + 1) / $($stylesheets.Count)" }

        $css = Invoke-WebRequest -Uri $cssUrl -UseBasicParsing -TimeoutSec 120
        foreach ($match in [regex]::Matches([string]$css.Content, '(?i)url\(["'']?(?<u>[^"''\)]+\.(?:ttf|otf|zip)(?:\?[^"''\)]*)?)["'']?\)')) {
            $absolute = Resolve-BfdAbsoluteUrl -BaseUrl $cssUrl -Candidate ([string]$match.Groups["u"].Value)
            if ([string]::IsNullOrWhiteSpace($absolute)) { continue }
            if ($seen.ContainsKey($absolute)) { continue }
            $seen[$absolute] = $true
            $assetUrls.Add($absolute) | Out-Null
        }
    }

    if ($assetUrls.Count -eq 0) {
        throw "Open Foundry did not expose downloadable .ttf/.otf assets via HTML/CSS."
    }

    $count = Invoke-BfdDownloadUrlBatch -Provider $Provider -Urls $assetUrls.ToArray() -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath -Label "Open Foundry"
    if ($count -le 0) {
        throw "Open Foundry produced no .ttf/.otf files."
    }

    return $count
}
function Invoke-BfdProviderMethod {
    param(
        [Parameter(Mandatory = $true)][object]$Provider,
        [Parameter(Mandatory = $true)][ValidateSet("direct", "api", "html")][string]$Method,
        [Parameter(Mandatory = $true)][string]$ProviderOutput,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][string]$GoogleApiKey,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    switch ($Method) {
        "direct" {
            return Invoke-BfdDirectMethod -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath
        }
        "api" {
            switch ([string]$Provider.apiKind) {
                "google" { return Invoke-BfdGoogleApiMethod -Provider $Provider -ProviderOutput $ProviderOutput -GoogleApiKey $GoogleApiKey -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
                "fontshare" { return Invoke-BfdFontShareApiMethod -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
                default { throw "No API implementation configured for this provider." }
            }
        }
        "html" {
            switch ([string]$Provider.id) {
                "font_hub" { return Invoke-BfdHtmlMethod_FontHub -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
                "dafont" { return Invoke-BfdHtmlMethod_DaFont -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
                "befonts" { return Invoke-BfdHtmlMethod_BeFonts -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
                "open_foundry" { return Invoke-BfdHtmlMethod_OpenFoundry -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
                default { return Invoke-BfdHtmlMethod_Generic -Provider $Provider -ProviderOutput $ProviderOutput -TempRoot $TempRoot -EventCallback $EventCallback -StopSignalPath $StopSignalPath }
            }
        }
    }
}

function Invoke-BfdRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string[]]$Providers = (Get-BfdDefaultProviders),
        [Parameter(Mandatory = $false)][ValidateSet("direct", "api", "html")][string[]]$MethodOrder = @("direct", "api", "html"),
        [Parameter(Mandatory = $false)][string]$DownloadsRoot = (Join-Path $env:USERPROFILE "Downloads"),
        [Parameter(Mandatory = $false)][string]$BaseFolderName = "BFD Fonts",
        [Parameter(Mandatory = $false)][string]$DateFormat = "yyyy-MM-dd",
        [Parameter(Mandatory = $false)][string]$GoogleApiKey = $env:GOOGLE_FONTS_API_KEY,
        [Parameter(Mandatory = $false)][scriptblock]$EventCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    Enable-BfdTls
    $registry = Get-BfdProviderRegistry
    $selected = Resolve-BfdProviders -Providers $Providers -Registry $registry

    $outputRoot = Join-Path $DownloadsRoot $BaseFolderName
    $outputFolder = Get-BfdUniqueDatedOutputFolder -RootPath $outputRoot -DateFormat $DateFormat

    $runStart = Get-Date
    $providerSummaries = New-Object "System.Collections.Generic.List[object]"
    $totalFonts = 0

    for ($pi = 0; $pi -lt $selected.Count; $pi++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $provider = $selected[$pi]
        $providerOutput = Join-Path $outputFolder $provider.id
        Ensure-BfdDirectory -Path $providerOutput

        Invoke-BfdEvent -Callback $EventCallback -Event "provider_started" -Data @{ provider = $provider.id; providerName = $provider.displayName; index = $pi + 1; total = $selected.Count }

        $attempts = New-Object "System.Collections.Generic.List[object]"
        $success = $false
        $methodUsed = $null
        $fontCount = 0

        for ($mi = 0; $mi -lt $MethodOrder.Count; $mi++) {
            $method = $MethodOrder[$mi].ToLowerInvariant()
            $attemptStart = Get-Date
            $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("bfd-" + [guid]::NewGuid().ToString("N"))
            Ensure-BfdDirectory -Path $tempRoot

            Invoke-BfdEvent -Callback $EventCallback -Event "provider_attempt" -Data @{ provider = $provider.id; providerName = $provider.displayName; method = $method; index = $mi + 1; total = $MethodOrder.Count }
            try {
                $count = Invoke-BfdProviderMethod -Provider $provider -Method $method -ProviderOutput $providerOutput -TempRoot $tempRoot -GoogleApiKey $GoogleApiKey -EventCallback $EventCallback -StopSignalPath $StopSignalPath
                if ($count -le 0) {
                    throw "Method produced zero fonts."
                }
                $success = $true
                $methodUsed = $method
                $fontCount = (Get-BfdFontFiles -Path $providerOutput).Count
                $attempts.Add([pscustomobject]@{ method = $method; status = "success"; message = "Method succeeded"; startedAt = $attemptStart.ToString("o"); finishedAt = (Get-Date).ToString("o"); durationSeconds = [math]::Round(((Get-Date) - $attemptStart).TotalSeconds, 2); fontCount = $fontCount }) | Out-Null
                break
            }
            catch {
                $attempts.Add([pscustomobject]@{ method = $method; status = "failed"; message = $_.Exception.Message; startedAt = $attemptStart.ToString("o"); finishedAt = (Get-Date).ToString("o"); durationSeconds = [math]::Round(((Get-Date) - $attemptStart).TotalSeconds, 2); fontCount = 0 }) | Out-Null
                Invoke-BfdEvent -Callback $EventCallback -Event "provider_attempt_failed" -Data @{ provider = $provider.id; providerName = $provider.displayName; method = $method; message = $_.Exception.Message }
            }
            finally {
                if (Test-Path -LiteralPath $tempRoot) {
                    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $status = if ($success) { "success" } else { "skipped" }
        if ($success) { $totalFonts += $fontCount }

        $summary = [pscustomobject]@{
            providerId = $provider.id
            providerName = $provider.displayName
            status = $status
            methodUsed = $methodUsed
            fontCount = $fontCount
            outputFolder = $providerOutput
            attempts = $attempts.ToArray()
        }
        $providerSummaries.Add($summary) | Out-Null

        Invoke-BfdEvent -Callback $EventCallback -Event "provider_completed" -Data @{ provider = $provider.id; providerName = $provider.displayName; status = $status; methodUsed = $methodUsed; fontCount = $fontCount; outputFolder = $providerOutput }
    }

    $runEnd = Get-Date
    $summaryObject = [pscustomobject]@{
        generatedAt = $runEnd.ToString("o")
        startedAt = $runStart.ToString("o")
        finishedAt = $runEnd.ToString("o")
        durationSeconds = [math]::Round(($runEnd - $runStart).TotalSeconds, 2)
        outputFolder = $outputFolder
        providersSelected = @($selected | ForEach-Object { $_.id })
        methodOrder = $MethodOrder
        totalProviders = $selected.Count
        successfulProviders = @($providerSummaries | Where-Object { $_.status -eq "success" }).Count
        skippedProviders = @($providerSummaries | Where-Object { $_.status -ne "success" }).Count
        totalFonts = $totalFonts
        providers = $providerSummaries.ToArray()
    }

    $summaryPath = Join-Path $outputFolder "download-summary.json"
    $summaryObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return $summaryObject
}

function Test-BfdAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-BfdFonts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FontsRoot,
        [Parameter(Mandatory = $false)][ValidateSet("currentuser", "allusers")][string]$Scope = "currentuser",
        [Parameter(Mandatory = $false)][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $false)][string]$StopSignalPath
    )

    $fonts = Get-BfdFontFiles -Path $FontsRoot
    if ($fonts.Count -eq 0) {
        throw "No .ttf/.otf files found under $FontsRoot"
    }

    if ($Scope -eq "allusers") {
        if (-not (Test-BfdAdministrator)) {
            throw "allusers install requires elevated terminal"
        }
        $fontsDir = Join-Path $env:WINDIR "Fonts"
        $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    }
    else {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
        $fontsDir = Join-Path $localAppData "Microsoft\Windows\Fonts"
        $registryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    }

    Ensure-BfdDirectory -Path $fontsDir
    if (-not (Test-Path -LiteralPath $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }

    if (-not ("Bfd.FontApi" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FontApi {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string lpFileName);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg,UIntPtr wParam,IntPtr lParam,uint fuFlags,uint uTimeout,out UIntPtr lpdwResult);
}
"@ -Namespace Bfd
    }

    $succeeded = 0
    $failed = 0
    for ($i = 0; $i -lt $fonts.Count; $i++) {
        Assert-BfdNotStopped -StopSignalPath $StopSignalPath
        $font = $fonts[$i]
        try {
            $targetPath = Join-Path $fontsDir $font.Name
            if (-not (Test-Path -LiteralPath $targetPath)) {
                Copy-Item -LiteralPath $font.FullName -Destination $targetPath -Force
            }
            $suffix = if ($font.Extension.ToLowerInvariant() -eq ".otf") { "(OpenType)" } else { "(TrueType)" }
            $name = "{0} {1}" -f $font.BaseName, $suffix
            $value = if ($Scope -eq "allusers") { $font.Name } else { $targetPath }
            New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType String -Force | Out-Null
            [void][Bfd.FontApi]::AddFontResource($targetPath)
            $succeeded++
        }
        catch {
            $failed++
        }

        $current = $i + 1
        $percent = [math]::Round((100.0 * $current) / $fonts.Count, 2)
        Invoke-BfdEvent -Callback $ProgressCallback -Event "install_progress" -Data @{ current = $current; total = $fonts.Count; percent = $percent; font = $font.Name; succeeded = $succeeded; failed = $failed }
    }

    $broadcast = [UIntPtr]::Zero
    [void][Bfd.FontApi]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$broadcast)

    return [pscustomobject]@{ total = $fonts.Count; succeeded = $succeeded; failed = $failed; scope = $Scope }
}

Export-ModuleMember -Function @("Get-BfdProviderRegistry", "Get-BfdDefaultProviders", "Invoke-BfdRun", "Install-BfdFonts")
