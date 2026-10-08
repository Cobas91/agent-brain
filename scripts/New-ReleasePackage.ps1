#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Ref='HEAD',
    [string]$OutputPath,
    [switch]$Force
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {throw 'Git is required to build a release package from tracked source.'}
if (-not $OutputPath) {$OutputPath=Join-Path $projectRoot 'dist/agent-brain.zip'}
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {throw 'Output already exists. Choose another path or use -Force to replace the generated archive.'}
$target=& git -C $projectRoot rev-parse --verify --end-of-options ($Ref+'^{commit}')
if ($LASTEXITCODE -ne 0) {throw 'Ref must resolve to an existing commit.'}
$files=@(& git -C $projectRoot ls-tree -r --name-only $target)
if ($LASTEXITCODE -ne 0) {throw 'Unable to inspect tracked release files.'}
foreach ($file in $files) {
    if ($file -match '(^|/)(\.env(?:\..*)?|backups|logs|\.git|\.idea|__pycache__|\.pytest_cache|installer-state\.json)(/|$)' -or $file -match '\.(zip|dump|bak|partial)$') {
        throw ('Private/runtime/archive file is tracked; remove it before releasing: '+$file)
    }
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
& git -C $projectRoot archive --format=zip --prefix=agent-brain/ --output $OutputPath $target
if ($LASTEXITCODE -ne 0) {throw 'Git archive failed. No release should be uploaded.'}
Write-Host ('Release package: '+$OutputPath)
Write-Host ('Commit: '+$target)
Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant())
