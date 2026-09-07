param(
    [string]$Flutter = 'flutter',
    [string]$EnvFile = '.env',
    [string]$InstallerCompiler,
    [string]$CrtDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    if (!$CrtDirectory) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        $redist = Get-ChildItem (Join-Path $visualStudio 'VC/Redist/MSVC') -Directory |
            Where-Object Name -Match '^\d+\.\d+\.\d+$' |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        $CrtDirectory = (Get-ChildItem (Join-Path $redist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
            Select-Object -First 1).FullName
    }
    if (!$CrtDirectory -or !(Test-Path (Join-Path $CrtDirectory 'vcruntime140.dll'))) {
        throw 'The Visual C++ x64 redistributable DLLs are required. Supply -CrtDirectory.'
    }
    $credentials = @{}
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        if ($line -match '^\s*(desktopclientid|desktopclientsecret)\s*=(.*)$') {
            $credentials[$Matches[1]] = $Matches[2].Trim()
        }
    }
    if (!$credentials.desktopclientid -or !$credentials.desktopclientsecret) {
        throw 'The .env file must contain desktopclientid and desktopclientsecret.'
    }

    New-Item -ItemType Directory -Path build -Force | Out-Null
    $definesPath = Join-Path $projectRoot 'build/windows-oauth.json'
    @{
        MARIO_DESKTOP_CLIENT_ID = $credentials.desktopclientid
        MARIO_DESKTOP_CLIENT_SECRET = $credentials.desktopclientsecret
    } | ConvertTo-Json | Set-Content -LiteralPath $definesPath -Encoding ascii

    try {
        & $Flutter build windows --release "--dart-define-from-file=$definesPath"
        if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    } finally {
        Remove-Item -LiteralPath $definesPath -Force
    }

    $versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)'
    $version = $versionLine.Matches[0].Groups[1].Value.Replace('+', '-')
    Copy-Item -Path (Join-Path $CrtDirectory '*.dll') -Destination 'build/windows/x64/runner/Release' -Force
    $archive = Join-Path $projectRoot "build/mario-$version-windows-x64.zip"
    Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath $archive -Force
    Get-FileHash -LiteralPath $archive -Algorithm SHA256 |
        ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $archive -Leaf)" } |
        Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
    Write-Output "Windows release: $archive"

    if ($InstallerCompiler) {
        $appVersion = $versionLine.Matches[0].Groups[1].Value.Split('+')[0]
        & $InstallerCompiler "/DAppVersion=$appVersion" "/DArtifactVersion=$version" 'packaging/windows/mario.iss'
        if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed.' }
        $installer = Join-Path $projectRoot "build/mario-$version-windows-x64-setup.exe"
        Get-FileHash -LiteralPath $installer -Algorithm SHA256 |
            ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $installer -Leaf)" } |
            Set-Content -LiteralPath "$installer.sha256" -Encoding ascii
        Write-Output "Windows installer: $installer"
    }
} finally {
    Pop-Location
}
