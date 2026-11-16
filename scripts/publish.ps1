<#
.SYNOPSIS
    发布：本地校验 -> 提交 -> 推送到 master -> 触发 GitHub Actions 部署。

.DESCRIPTION
    推送后由 .github/workflows/jekyll.yml 构建并发布到 GitHub Pages，
    通常 1-3 分钟后 https://bo-wang-em.github.io 生效。

.PARAMETER Message
    提交信息。省略时自动生成 "更新个人主页 yyyy-MM-dd HH:mm"。

.PARAMETER SkipBuild
    跳过本地构建校验（不推荐）。

.PARAMETER DryRun
    只看本次会提交哪些文件，不做任何改动。

.PARAMETER NoPush
    只提交不推送。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\publish.ps1 -Message "新增 2026 年论文"
#>
[CmdletBinding()]
param(
    [string]$Message,
    [switch]$SkipBuild,
    [switch]$DryRun,
    [switch]$NoPush,
    [string]$Remote = 'origin',
    [string]$Branch = 'master'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$root = Get-RepoRoot
Set-Location $root
Initialize-BundleEnvironment

Write-Host ""
Write-Host "个人主页发布流程" -ForegroundColor White

# ---------------------------------------------------------------- 1. 仓库检查
Write-Step "1/4 检查仓库状态"
if (-not (Test-Path (Join-Path $root '.git'))) {
    throw "当前目录不是 Git 仓库：$root"
}

$currentBranch = Get-NativeOutput -Exe 'git' -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
if ($currentBranch -ne $Branch) {
    Write-Fail "当前分支是 $currentBranch，发布分支是 $Branch"
    Write-Host "    切换分支：git switch $Branch"
    throw "分支不匹配"
}

$remoteUrl = Get-NativeOutput -Exe 'git' -Arguments @('remote', 'get-url', $Remote)
if (-not $remoteUrl) {
    throw "找不到远端 $Remote"
}
Write-Ok "分支 $Branch -> $remoteUrl"

# ---------------------------------------------------------------- 2. 构建校验
if ($SkipBuild) {
    Write-Step "2/4 跳过构建校验（-SkipBuild）"
}
else {
    Write-Step "2/4 以生产模式构建并校验"
    $buildScript = Join-Path $root 'scripts\build.ps1'
    & $buildScript
    if (-not $?) { throw "构建或校验失败，已中止发布" }
    Write-Ok "构建校验通过"
}

# ---------------------------------------------------------------- 3. 提交
Write-Step "3/4 收集改动"
$statusText = Get-NativeOutput -Exe 'git' -Arguments @('status', '--porcelain')
$lines = @($statusText -split "`r?`n" | Where-Object { $_.Trim() -ne '' })

if ($lines.Count -eq 0) {
    Write-Warn "没有需要提交的改动"
    if (-not $NoPush) {
        Write-Host "    若只是想把已有提交推上去：git push $Remote $Branch"
    }
    return
}

$modified = @($lines | Where-Object { $_ -notmatch '^\?\?' })
$added = @($lines | Where-Object { $_ -match '^\?\?' })
Write-Host "    改动 $($modified.Count) 个 / 新增 $($added.Count) 个：" -ForegroundColor DarkGray
$lines | Select-Object -First 30 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
if ($lines.Count -gt 30) { Write-Host "      ... 共 $($lines.Count) 项" -ForegroundColor DarkGray }

if ($DryRun) {
    Write-Step "DryRun：不提交、不推送"
    return
}

if (-not $Message) {
    $Message = "更新个人主页 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

Invoke-Git @('add', '-A') | Out-Null
Invoke-Git @('commit', '-m', $Message) -Quiet | Out-Null
Write-Ok "已提交：$Message"

# ---------------------------------------------------------------- 4. 推送
if ($NoPush) {
    Write-Step "4/4 已按 -NoPush 停止，提交尚未推送"
    return
}

Write-Step "4/4 推送到 $Remote/$Branch"
$pushCode = Invoke-Git @('push', $Remote, $Branch) -AllowFailure
if ($pushCode -ne 0) {
    Write-Fail "推送失败"
    Write-Host "    常见原因：" -ForegroundColor Yellow
    Write-Host "      1) 需要登录：首次推送会弹出 Git Credential Manager，按提示授权 GitHub" -ForegroundColor Yellow
    Write-Host "      2) 弹窗不可用时改用 Personal Access Token：" -ForegroundColor Yellow
    Write-Host "         git push https://<用户名>:<PAT>@github.com/Bo-Wang-EM/Bo-Wang-EM.github.io.git $Branch" -ForegroundColor Yellow
    Write-Host "      3) TLS 报错：重新执行 scripts\setup.ps1" -ForegroundColor Yellow
    throw "推送失败"
}

Write-Host ""
Write-Ok "已推送，GitHub Actions 开始构建"
Write-Host "    构建进度：https://github.com/Bo-Wang-EM/Bo-Wang-EM.github.io/actions" -ForegroundColor Cyan
Write-Host "    线上地址：https://bo-wang-em.github.io" -ForegroundColor Cyan
Write-Host "    一般 1-3 分钟生效；Actions 失败时线上仍是上一个版本" -ForegroundColor DarkGray
Write-Host ""
