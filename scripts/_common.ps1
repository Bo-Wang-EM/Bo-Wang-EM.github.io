# 公共函数：所有脚本通过 dot-source 引用本文件
# 作用：统一仓库根目录、Bundler 本地环境变量、命令执行与日志

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoRoot {
    return $script:RepoRoot
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "    [OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "    [!] $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "    [X] $Text" -ForegroundColor Red
}

# 把 Bundler 的缓存/可执行文件目录固定在仓库内，
# 既避免污染 %USERPROFILE%\.bundle，也让整套环境可随时删除重装
function Initialize-BundleEnvironment {
    $root = $script:RepoRoot
    $env:BUNDLE_USER_CACHE = Join-Path $root '.bundle\user-cache'
    $env:BUNDLE_SYSTEM_BINDIR = Join-Path $root '.bundle\bin'
    $env:BUNDLE_JOBS = '4'
    # Windows 控制台默认代码页会导致 Jekyll 中文日志乱码
    $env:LANG = 'en_US.UTF-8'
    $env:LC_ALL = 'en_US.UTF-8'
}

function Assert-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Fail "找不到命令：$Name"
        if ($Hint) { Write-Host "    $Hint" }
        throw "缺少依赖：$Name"
    }
}

# 原生命令（bundle / git / ruby）会把警告写到 stderr，
# 在 $ErrorActionPreference='Stop' 下会被 PowerShell 当成终止性错误。
# 这里临时降级错误策略并合并输出，只以退出码判定成败。
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [switch]$Quiet
    )

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Push-Location $script:RepoRoot
        try {
            if ($Quiet) {
                & $Exe @Arguments 2>&1 | Out-Null
            }
            else {
                & $Exe @Arguments 2>&1 | Out-Host
            }
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
    return $code
}

# 取原生命令的标准输出（例如 ruby -v、git rev-parse）
function Get-NativeOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @()
    )
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Push-Location $script:RepoRoot
        try {
            $output = & $Exe @Arguments 2>$null
            return (($output | Out-String).Trim())
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
}

# 调用 bundle 并检查退出码
function Invoke-Bundle {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $code = Invoke-Native -Exe 'bundle' -Arguments $Arguments
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "bundle $($Arguments -join ' ') 执行失败（退出码 $code）"
    }
    return $code
}

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFailure, [switch]$Quiet)
    $code = Invoke-Native -Exe 'git' -Arguments $Arguments -Quiet:$Quiet
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') 执行失败（退出码 $code）"
    }
    return $code
}

# 依赖是否已就位（bundle check 通过）
function Test-BundleReady {
    $code = Invoke-Native -Exe 'bundle' -Arguments @('check') -Quiet
    return ($code -eq 0)
}

function Ensure-BundleReady {
    if (Test-BundleReady) { return }
    Write-Warn "Ruby 依赖未安装或不完整，正在执行 bundle install ..."
    Invoke-Bundle @('install', '--retry', '3')
}
