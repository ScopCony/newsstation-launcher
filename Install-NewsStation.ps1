[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $NewsStationArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$NewsStationOwner = 'ScopCony'
$NewsStationRepo = 'newsstation-backend'
$NewsStationBranch = 'main'
$NewsStationUvVersion = '0.11.32'
$NewsStationBootstrapUrl = 'https://raw.githubusercontent.com/ScopCony/newsstation-launcher/main/Install-NewsStation.ps1'
$NewsStationApi = "https://api.github.com/repos/$NewsStationOwner/$NewsStationRepo"
$NewsStationHome = Join-Path $env:LOCALAPPDATA 'NewsStation'
$NewsStationVersions = Join-Path $NewsStationHome 'versions'
$NewsStationTools = Join-Path $NewsStationHome 'tools'
$NewsStationSecrets = Join-Path $NewsStationHome 'secrets'
$NewsStationConfig = Join-Path $NewsStationHome 'environment'
$NewsStationCurrent = Join-Path $NewsStationHome 'current.sha'
$NewsStationLauncher = Join-Path $NewsStationHome 'launcher.ps1'
$NewsStationCommand = Join-Path $NewsStationHome 'NewsStation.cmd'
$NewsStationUv = Join-Path $NewsStationTools 'uv.exe'

function Write-NewsStationInfo {
    param([string] $Message)
    Write-Host $Message
}

function Stop-NewsStation {
    param([string] $Message)
    throw "NewsStation: $Message"
}

function Save-TextAtomically {
    param(
        [string] $Path,
        [string] $Value
    )

    $temporaryPath = Join-Path $NewsStationHome ('.write-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($temporaryPath, $Value, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-RememberedEnvironment {
    if (Test-Path -LiteralPath $NewsStationConfig -PathType Leaf) {
        return ([IO.File]::ReadAllText($NewsStationConfig)).Trim()
    }
    return ''
}

function Get-EnvironmentOnce {
    $remembered = Get-RememberedEnvironment
    if ($remembered) {
        if ($remembered -ne 'windows') {
            Stop-NewsStation "Zapamiętane środowisko '$remembered' nie pasuje do Windows."
        }
        return 'windows'
    }

    Write-NewsStationInfo ''
    Write-NewsStationInfo 'NewsStation — pierwsze uruchomienie'
    Write-NewsStationInfo 'Wybierz środowisko:'
    Write-NewsStationInfo '  1. Windows 11'
    $choice = Read-Host 'Numer środowiska'
    if ($choice -ne '1') {
        Stop-NewsStation 'Nieprawidłowy wybór środowiska.'
    }

    Save-TextAtomically -Path $NewsStationConfig -Value "windows`n"
    return 'windows'
}

function Get-PlainText {
    param([Security.SecureString] $SecureValue)
    $credential = [Management.Automation.PSCredential]::new('NewsStation', $SecureValue)
    return $credential.GetNetworkCredential().Password
}

function Get-SavedSecret {
    param([string] $Name)
    $path = Join-Path $NewsStationSecrets "$Name.txt"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }

    $encrypted = ([IO.File]::ReadAllText($path)).Trim()
    if (-not $encrypted) {
        return ''
    }
    return (Get-PlainText (ConvertTo-SecureString $encrypted))
}

function Save-Secret {
    param(
        [string] $Name,
        [Security.SecureString] $SecureValue
    )
    $path = Join-Path $NewsStationSecrets "$Name.txt"
    $encrypted = ConvertFrom-SecureString $SecureValue
    Save-TextAtomically -Path $path -Value "$encrypted`n"
}

function Get-OrAskSecret {
    param(
        [string] $Name,
        [string] $Label,
        [switch] $Visible
    )

    $saved = Get-SavedSecret $Name
    if ($saved) {
        return $saved
    }

    if ($Visible) {
        $plain = Read-Host $Label
        if (-not $plain) {
            Stop-NewsStation "Nie podano wartości: $Label"
        }
        $secure = ConvertTo-SecureString $plain -AsPlainText -Force
    }
    else {
        $secure = Read-Host $Label -AsSecureString
        $plain = Get-PlainText $secure
        if (-not $plain) {
            Stop-NewsStation "Nie podano wartości: $Label"
        }
    }

    if ($plain.Contains("`r") -or $plain.Contains("`n")) {
        Stop-NewsStation "Wartość '$Label' zawiera niedozwolony znak końca linii."
    }
    Save-Secret -Name $Name -SecureValue $secure
    return $plain
}

function Get-GitHubHeaders {
    param([string] $Token)
    return @{
        Accept                 = 'application/vnd.github+json'
        Authorization          = "Bearer $Token"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'NewsStation-bootstrap'
    }
}

function Get-LatestCommitSha {
    param([string] $Token)
    $request = @{
        Uri     = "$NewsStationApi/commits/$NewsStationBranch"
        Headers = (Get-GitHubHeaders $Token)
        Method  = 'Get'
    }
    $response = Invoke-RestMethod @request
    $sha = [string] $response.sha
    if ($sha -notmatch '^[0-9a-f]{40}$') {
        Stop-NewsStation 'GitHub zwrócił nieprawidłowy numer wersji.'
    }
    return $sha
}

function Get-VersionContainer {
    param([string] $Sha)
    return Join-Path $NewsStationVersions $Sha
}

function Get-VersionSource {
    param([string] $Sha)
    if ($Sha -notmatch '^[0-9a-f]{40}$') {
        return ''
    }
    $container = Get-VersionContainer $Sha
    $sourceNameFile = Join-Path $container '.source-name'
    if (-not (Test-Path -LiteralPath $sourceNameFile -PathType Leaf)) {
        return ''
    }

    $sourceName = ([IO.File]::ReadAllText($sourceNameFile)).Trim()
    if (-not $sourceName -or $sourceName.Contains('/') -or $sourceName.Contains('\')) {
        return ''
    }
    $source = Join-Path $container $sourceName
    if (-not (Test-Path -LiteralPath (Join-Path $source 'main.py') -PathType Leaf)) {
        return ''
    }
    return $source
}

function Test-VersionReady {
    param([string] $Sha)
    if ($Sha -notmatch '^[0-9a-f]{40}$') {
        return $false
    }
    $container = Get-VersionContainer $Sha
    return (
        (Test-Path -LiteralPath (Join-Path $container '.newsstation-ready') -PathType Leaf) -and
        [bool](Get-VersionSource $Sha)
    )
}

function Download-Version {
    param(
        [string] $Token,
        [string] $Sha
    )

    if (Test-VersionReady $Sha) {
        return (Get-VersionSource $Sha)
    }

    $container = Get-VersionContainer $Sha
    New-Item -ItemType Directory -Path $container -Force | Out-Null
    $archive = Join-Path $NewsStationHome ('.download-' + [Guid]::NewGuid().ToString('N') + '.zip')

    Write-NewsStationInfo 'Pobieram nową wersję programu...'
    $downloadRequest = @{
        Uri             = "$NewsStationApi/zipball/$Sha"
        Headers         = (Get-GitHubHeaders $Token)
        OutFile         = $archive
        UseBasicParsing = $true
    }
    Invoke-WebRequest @downloadRequest
    Expand-Archive -LiteralPath $archive -DestinationPath $container -Force
    Remove-Item -LiteralPath $archive -Force

    $sourceCandidates = @(
        Get-ChildItem -LiteralPath $container -Directory -Force |
            Where-Object {
                -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'main.py') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'requirements.txt') -PathType Leaf)
            }
    )
    if ($sourceCandidates.Count -ne 1) {
        Stop-NewsStation 'Pobrana paczka nie zawiera jednej kompletnej kopii programu.'
    }

    Save-TextAtomically -Path (Join-Path $container '.source-name') -Value ($sourceCandidates[0].Name + "`n")
    return $sourceCandidates[0].FullName
}

function Ensure-Uv {
    if (Test-Path -LiteralPath $NewsStationUv -PathType Leaf) {
        return
    }

    Write-NewsStationInfo 'Przygotowuję środowisko uruchomieniowe...'
    New-Item -ItemType Directory -Path $NewsStationTools -Force | Out-Null
    $installer = Join-Path $NewsStationHome ('.uv-install-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $installerRequest = @{
        Uri             = "https://astral.sh/uv/$NewsStationUvVersion/install.ps1"
        OutFile         = $installer
        UseBasicParsing = $true
    }
    Invoke-WebRequest @installerRequest

    $previousInstallPath = $env:UV_UNMANAGED_INSTALL
    $previousModifyPath = $env:UV_NO_MODIFY_PATH
    try {
        $env:UV_UNMANAGED_INSTALL = $NewsStationTools
        $env:UV_NO_MODIFY_PATH = '1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Stop-NewsStation 'Instalator uv zakończył się błędem.'
        }
    }
    finally {
        $env:UV_UNMANAGED_INSTALL = $previousInstallPath
        $env:UV_NO_MODIFY_PATH = $previousModifyPath
        if (Test-Path -LiteralPath $installer -PathType Leaf) {
            Remove-Item -LiteralPath $installer -Force
        }
    }

    if (-not (Test-Path -LiteralPath $NewsStationUv -PathType Leaf)) {
        Stop-NewsStation 'Nie udało się przygotować narzędzia uv.'
    }
}

function Prepare-Version {
    param(
        [string] $Sha,
        [string] $Source
    )
    $python = Join-Path $Source '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        & $NewsStationUv venv --python 3.12 (Join-Path $Source '.venv')
        if ($LASTEXITCODE -ne 0) {
            Stop-NewsStation 'Nie udało się utworzyć środowiska Pythona.'
        }
    }

    & $NewsStationUv pip sync --python $python (Join-Path $Source 'requirements.txt')
    if ($LASTEXITCODE -ne 0) {
        Stop-NewsStation 'Nie udało się zainstalować zależności programu.'
    }

    $ready = Join-Path (Get-VersionContainer $Sha) '.newsstation-ready'
    Save-TextAtomically -Path $ready -Value "ready`n"
}

function Get-CurrentSha {
    if (Test-Path -LiteralPath $NewsStationCurrent -PathType Leaf) {
        return ([IO.File]::ReadAllText($NewsStationCurrent)).Trim()
    }
    return ''
}

function Save-CurrentSha {
    param([string] $Sha)
    Save-TextAtomically -Path $NewsStationCurrent -Value "$Sha`n"
}

function Save-LocalLauncher {
    $temporaryLauncher = Join-Path $NewsStationHome ('.launcher-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    try {
        $launcherRequest = @{
            Uri             = $NewsStationBootstrapUrl
            OutFile         = $temporaryLauncher
            UseBasicParsing = $true
        }
        Invoke-WebRequest @launcherRequest
        Move-Item -LiteralPath $temporaryLauncher -Destination $NewsStationLauncher -Force
    }
    catch {
        if (Test-Path -LiteralPath $temporaryLauncher -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryLauncher -Force
        }
        if (-not (Test-Path -LiteralPath $NewsStationLauncher -PathType Leaf)) {
            return
        }
    }

    $commandText = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$NewsStationLauncher" %*
"@
    [IO.File]::WriteAllText($NewsStationCommand, $commandText, [Text.ASCIIEncoding]::new())

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathEntries = @($userPath -split ';' | Where-Object { $_ })
    if (-not ($pathEntries | Where-Object { $_.TrimEnd('\') -ieq $NewsStationHome.TrimEnd('\') })) {
        $newUserPath = if ($userPath) { "$userPath;$NewsStationHome" } else { $NewsStationHome }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    }
    if (-not (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $NewsStationHome.TrimEnd('\') })) {
        $env:Path = "$env:Path;$NewsStationHome"
    }
}

function Invoke-NewsStationProgram {
    param(
        [string] $Source,
        [string[]] $Arguments
    )

    $googleKey = Get-OrAskSecret -Name 'GOOGLE_API_KEY' -Label 'Klucz Google AI Studio'
    $supabaseUrl = Get-OrAskSecret -Name 'SUPABASE_URL' -Label 'Adres Supabase' -Visible
    $supabaseKey = Get-OrAskSecret -Name 'SUPABASE_SERVICE_KEY' -Label 'Klucz serwerowy Supabase'

    $env:GOOGLE_API_KEY = $googleKey
    $env:SUPABASE_URL = $supabaseUrl
    $env:SUPABASE_SERVICE_KEY = $supabaseKey
    $env:PYTHONUNBUFFERED = '1'

    Write-NewsStationInfo ''
    Write-NewsStationInfo 'Uruchamiam NewsStation...'
    Push-Location $Source
    try {
        $python = Join-Path $Source '.venv\Scripts\python.exe'
        & $python 'main.py' @Arguments
        if ($LASTEXITCODE -ne 0) {
            Stop-NewsStation "Program zakończył pracę z błędem (kod $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }
}

function Start-NewsStation {
    New-Item -ItemType Directory -Path $NewsStationHome, $NewsStationVersions, $NewsStationTools, $NewsStationSecrets -Force | Out-Null
    Get-EnvironmentOnce | Out-Null
    Save-LocalLauncher

    $githubToken = Get-OrAskSecret -Name 'GITHUB_TOKEN' -Label 'Token GitHuba tylko do odczytu'
    $currentSha = Get-CurrentSha
    $latestSha = ''

    try {
        $latestSha = Get-LatestCommitSha $githubToken
    }
    catch {
        if ($currentSha -and (Test-VersionReady $currentSha)) {
            Write-NewsStationInfo 'Nie udało się sprawdzić GitHuba. Uruchamiam ostatnią działającą kopię.'
        }
        else {
            Stop-NewsStation 'Nie udało się połączyć z prywatnym repozytorium i nie ma lokalnej kopii programu.'
        }
    }

    if ($latestSha) {
        if ($latestSha -eq $currentSha -and (Test-VersionReady $currentSha)) {
            Write-NewsStationInfo 'Lokalna kopia programu jest aktualna.'
        }
        else {
            try {
                $source = Download-Version -Token $githubToken -Sha $latestSha
                Ensure-Uv
                Prepare-Version -Sha $latestSha -Source $source
                Save-CurrentSha $latestSha
                $currentSha = $latestSha
                Write-NewsStationInfo 'Nowa wersja programu jest gotowa.'
            }
            catch {
                if ($currentSha -and (Test-VersionReady $currentSha)) {
                    Write-NewsStationInfo 'Aktualizacja nie powiodła się. Uruchamiam ostatnią działającą kopię.'
                }
                else {
                    Stop-NewsStation 'Nie udało się przygotować programu i nie ma lokalnej działającej kopii.'
                }
            }
        }
    }

    $currentSource = Get-VersionSource $currentSha
    if (-not $currentSource) {
        Stop-NewsStation 'Nie można odnaleźć gotowej lokalnej kopii programu.'
    }
    Invoke-NewsStationProgram -Source $currentSource -Arguments $NewsStationArguments
}

try {
    Start-NewsStation
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

