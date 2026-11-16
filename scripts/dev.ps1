<#
.SYNOPSIS
    启动本地预览服务器（改文件自动重建 + 浏览器热刷新）。

.DESCRIPTION
    等价于 bundle exec jekyll serve --livereload，额外做了三件事：
      1. 依赖缺失时自动 bundle install；
      2. 固定端口与监听地址，避免 Windows 防火墙弹窗；
      3. 关闭 Git 的 Windows 控制台彩色转义噪音。

.PARAMETER Port
    端口，默认 4000。

.PARAMETER Drafts
    同时渲染 _drafts/ 下的草稿（发布前不带上即可）。

.PARAMETER NoReload
    关闭浏览器热刷新（网络慢或页面多时更快）。

.EXAMPLE
    pwsh -File scripts/dev.ps1
    pwsh -File scripts/dev.ps1 -Port 4001 -Drafts
#>
[CmdletBinding()]
param(
    [int]$Port = 4000,
    [string]$BindAddress = '127.0.0.1',
    [switch]$Drafts,
    [switch]$NoReload
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$root = Get-RepoRoot
Set-Location $root
Initialize-BundleEnvironment

Assert-Command ruby "安装 Ruby 3.1+：https://rubyinstaller.org/downloads/"
Ensure-BundleReady

$jekyllArgs = @('exec', 'jekyll', 'serve', '--host', $BindAddress, '--port', $Port, '--trace')
if (-not $NoReload) { $jekyllArgs += '--livereload' }
if ($Drafts) { $jekyllArgs += '--drafts' }

# 端口占用时给出可执行的提示，而不是让 Jekyll 抛一屏栈
$inUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($inUse) {
    $ownerPid = ($inUse | Select-Object -First 1).OwningProcess
    $ownerName = (Get-Process -Id $ownerPid -ErrorAction SilentlyContinue).ProcessName
    Write-Warn "端口 $Port 已被占用（PID $ownerPid / $ownerName）"
    Write-Warn "换端口：pwsh -File scripts/dev.ps1 -Port $($Port + 1)"
    Write-Warn "或结束进程：Stop-Process -Id $ownerPid"
    throw "端口被占用"
}

Write-Host ""
Write-Host "本地预览：http://${BindAddress}:$Port" -ForegroundColor Green
if ($Drafts) { Write-Host "已启用 _drafts 草稿预览" -ForegroundColor DarkGray }
Write-Host "改动 _posts / _pages / _sass 会自动重建；改 _config.yml 需要重启" -ForegroundColor DarkGray
Write-Host "按 Ctrl+C 退出" -ForegroundColor DarkGray
Write-Host ""

Invoke-Bundle $jekyllArgs
