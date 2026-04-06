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

& (Join-Path $PSScriptRoot "BFD\cli\BFD.ps1") @PSBoundParameters
