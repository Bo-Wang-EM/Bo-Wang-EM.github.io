<#
.SYNOPSIS
    一次性准备本地 Jekyll 调试环境（Windows / Ruby 3.1+）。

.DESCRIPTION
    检查工具链 -> 固定 Bundler 目录 -> 修正 Git 的 TLS/代理设置 -> 安装 Ruby 依赖 -> 试构建一次。
    重复执行是安全的：已就绪的步骤会快速跳过。

.PARAMETER GemMirror
    RubyGems 镜像地址。默认清华 TUNA；设为空字符串 '' 则直连 Gemfile 里声明的源。

.PARAMETER SkipGitConfig
    跳过对 Git 的 TLS/代理修正。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [string]$GemMirror = 'https://mirrors.tuna.tsinghua.edu.cn/rubygems/',
    [switch]$SkipGitConfig
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$root = Get-RepoRoot
Set-Location $root
Initialize-BundleEnvironment

Write-Host ""
Write-Host "个人主页本地工作流 - 环境准备" -ForegroundColor White
Write-Host "仓库：$root"

# ---------------------------------------------------------------- 1. 工具链
Write-Step "1/5 检查工具链"

Assert-Command ruby "安装 Ruby+Devkit（3.1 或更高）：https://rubyinstaller.org/downloads/"
Assert-Command bundle "执行 gem install bundler"
Assert-Command node "安装 Node.js 18+：https://nodejs.org/"

$rubyVersion = Get-NativeOutput -Exe 'ruby' -Arguments @('-e', 'print RUBY_VERSION')
$nodeVersion = Get-NativeOutput -Exe 'node' -Arguments @('-v')
$bundlerVersion = (Get-NativeOutput -Exe 'bundle' -Arguments @('-v'))

$parts = $rubyVersion.Split('.')
if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 1)) {
    Write-Fail "Ruby 版本过低：$rubyVersion（需要 3.1+）"
    throw "请升级 Ruby"
}
Write-Ok "ruby $rubyVersion / node $nodeVersion / bundler $bundlerVersion"

# ---------------------------------------------------------------- 2. Bundler
Write-Step "2/5 配置 Bundler（依赖装在仓库内，不污染用户目录）"

Invoke-Bundle @('config', 'set', '--local', 'path', 'vendor/bundle') | Out-Null
Invoke-Bundle @('config', 'set', '--local', 'bin', '.bundle/bin') | Out-Null
if ($GemMirror) {
    # Gemfile 里写的是官方源（GitHub Actions 能直连）；本机网络访问官方源不稳，这里只做本机镜像映射，不改动 Gemfile
    Invoke-Bundle @('config', 'set', '--local', 'mirror.https://rubygems.org', $GemMirror) | Out-Null
    Invoke-Bundle @('config', 'unset', '--local', 'mirror.https://gems.ruby-china.com') -AllowFailure | Out-Null
    Write-Ok "RubyGems 镜像：$GemMirror"
}
else {
    Invoke-Bundle @('config', 'unset', '--local', 'mirror.https://rubygems.org') -AllowFailure | Out-Null
    Invoke-Bundle @('config', 'unset', '--local', 'mirror.https://gems.ruby-china.com') -AllowFailure | Out-Null
    Write-Ok "RubyGems 直连 Gemfile 声明的源"
}

# ---------------------------------------------------------------- 3. Git
if ($SkipGitConfig) {
    Write-Step "3/5 跳过 Git 配置（-SkipGitConfig）"
}
else {
    Write-Step "3/5 修正 Git 的 TLS 后端（仅对本仓库生效）"
    Invoke-Git @('config', '--local', 'http.sslBackend', 'openssl') | Out-Null
    Invoke-Git @('config', '--local', 'core.quotepath', 'false') | Out-Null
    Write-Ok "http.sslBackend=openssl（绕开 Windows schannel 的 SEC_E_NO_CREDENTIALS）"

    # 顺便验证一次能否连上远端，避免发布时才发现网络/代理问题
    $proxySetting = Get-NativeOutput -Exe 'git' -Arguments @('config', '--get', 'http.proxy')
    $probe = Get-NativeOutput -Exe 'git' -Arguments @('ls-remote', '--heads', 'origin')
    if ($probe) {
        if ($proxySetting) {
            Write-Ok "已连上远端仓库（沿用你原有的代理：$proxySetting）"
        }
        else {
            Write-Ok "已连上远端仓库（未使用代理）"
        }
    }
    else {
        Write-Warn "暂时连不上远端，可能是代理/网络问题；不影响本地构建"
        Write-Warn "需要代理时：git config --local http.proxy http://127.0.0.1:7890"
    }
}

# ---------------------------------------------------------------- 4. 依赖
Write-Step "4/5 安装 Ruby 依赖（首次要编译原生扩展，可能 5-20 分钟）"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Invoke-Bundle @('install', '--retry', '3') | Out-Null
$sw.Stop()
Write-Ok ("bundle install 完成，用时 {0:N1} 分钟" -f $sw.Elapsed.TotalMinutes)

# ---------------------------------------------------------------- 5. 试构建
Write-Step "5/5 试构建一次（验证环境可用）"
Invoke-Bundle @('exec', 'jekyll', 'build') | Out-Null
if (Test-Path (Join-Path $root '_site\index.html')) {
    Write-Ok "构建成功：_site\index.html"
}
else {
    Write-Fail "构建没有产出 _site\index.html"
    throw "构建校验失败"
}

Write-Host ""
Write-Host "环境就绪。接下来：" -ForegroundColor White
Write-Host "    scripts\dev.ps1      本地预览 http://127.0.0.1:4000"
Write-Host "    scripts\publish.ps1  校验后提交并推送"
Write-Host ""
