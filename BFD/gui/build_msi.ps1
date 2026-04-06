[CmdletBinding()]
param(
    [string]$ProductVersion = "1.0.0",
    [string]$Manufacturer = "BFD (Bulk Font Downloader)",
    [string]$UpgradeCode = "A2F0E6A1-4974-4F1D-A4B0-26D649101000",
    [string]$ExePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distExe = if ([string]::IsNullOrWhiteSpace($ExePath)) { Join-Path $scriptDir "dist\BFD.exe" } else { $ExePath }
if (-not (Test-Path -LiteralPath $distExe)) {
    throw "EXE not found at $distExe. Run build_exe.ps1 first."
}

function Get-WixCliPath {
    $cmd = Get-Command wix.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidate = "C:\Program Files\WiX Toolset v6.0\bin\wix.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }

    throw "WiX CLI not found."
}

$wixExe = Get-WixCliPath
$installerDir = Join-Path $scriptDir "installer"
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

$wxsPath = Join-Path $installerDir "BFD.wxs"
$msiPath = Join-Path $scriptDir "dist\BFD-$ProductVersion.msi"

$wxs = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="BFD (Bulk Font Downloader)"
           Manufacturer="$Manufacturer"
           Version="$ProductVersion"
           UpgradeCode="$UpgradeCode"
           Scope="perMachine">
    <MajorUpgrade DowngradeErrorMessage="A newer version of BFD is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="BFD" />
    </StandardDirectory>

    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="ApplicationProgramsFolder" Name="BFD" />
    </StandardDirectory>

    <Component Id="MainExecutableComponent" Directory="INSTALLFOLDER" Guid="*">
      <File Id="MainExecutableFile" Source="$distExe" KeyPath="yes" />
    </Component>

    <Component Id="StartMenuShortcutComponent" Directory="ApplicationProgramsFolder" Guid="*">
      <Shortcut Id="ApplicationStartMenuShortcut"
                Name="BFD"
                Description="Bulk Font Downloader"
                Target="[INSTALLFOLDER]BFD.exe"
                WorkingDirectory="INSTALLFOLDER" />
      <RemoveFolder Id="RemoveAppProgramMenuDir" On="uninstall" />
      <RegistryValue Root="HKLM" Key="Software\$Manufacturer\BFD" Name="installed" Type="integer" Value="1" KeyPath="yes" />
    </Component>

    <Feature Id="MainFeature" Title="BFD" Level="1">
      <ComponentRef Id="MainExecutableComponent" />
      <ComponentRef Id="StartMenuShortcutComponent" />
    </Feature>
  </Package>
</Wix>
"@

Set-Content -LiteralPath $wxsPath -Value $wxs -Encoding UTF8
& $wixExe build $wxsPath -arch x64 -o $msiPath

Write-Host ("MSI build completed: {0}" -f $msiPath)
