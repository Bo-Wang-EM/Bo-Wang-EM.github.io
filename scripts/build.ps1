<#
.SYNOPSIS
    以线上相同的方式构建站点，并做产物校验。

.DESCRIPTION
    与 GitHub Actions 的构建命令保持一致（JEKYLL_ENV=production + bundle exec jekyll build），
    因此"本地构建通过"基本等于"线上构建通过"。
    构建后运行 scripts/check-site.mjs 检查 Liquid 报错、站内死链、缺失图片。

.PARAMETER StrictLinks
    站内死链也视为失败（默认只警告）。

.PARAMETER SkipChecks
    只构建，不做产物校验。

.EXAMPLE
    pwsh -File scripts/build.ps1
#>
[CmdletBinding()]
param(
    [switch]$StrictLinks,
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$root = Get-RepoRoot
Set-Location $root
Initialize-BundleEnvironment

Ensure-BundleReady

Write-Step "以生产模式构建（JEKYLL_ENV=production）"
$env:JEKYLL_ENV = 'production'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Invoke-Bundle @('exec', 'jekyll', 'build', '--trace') | Out-Null
$sw.Stop()
Write-Ok ("构建完成，用时 {0:N1} 秒" -f $sw.Elapsed.TotalSeconds)

$indexPath = Join-Path $root '_site\index.html'
if (-not (Test-Path $indexPath)) {
    Write-Fail "没有生成 _site\index.html"
    throw "构建失败"
}

if ($SkipChecks) {
    Write-Warn "已跳过产物校验（-SkipChecks）"
    return
}

Write-Step "校验构建产物"
$checkArgs = @((Join-Path $root 'scripts\check-site.mjs'), (Join-Path $root '_site'))
if ($StrictLinks) { $checkArgs += '--strict' }
& node @checkArgs
if ($LASTEXITCODE -ne 0) {
    throw "产物校验未通过"
}
