# 个人主页工作流（本地调试 → 上传发布）

仓库：<https://github.com/Bo-Wang-EM/Bo-Wang-EM.github.io>
线上：<https://bo-wang-em.github.io>
技术栈：Jekyll（Academic Pages 主题）+ GitHub Actions + GitHub Pages

---

## 1. 整体结构：本地负责"看"，Actions 负责"发"

```
本地编辑 ──> jekyll serve (:4000) ──> 满意 ──> git push master
                                                    │
                                                    ▼
                                  GitHub Actions (.github/workflows/jekyll.yml)
                                  bundle exec jekyll build
                                                    │
                                                    ▼
                                     GitHub Pages → https://bo-wang-em.github.io
```

两条关键事实：

1. **本地和线上用同一份 Gemfile、同一条构建命令**，所以本地能构建，线上就能构建。
2. **`_site/` 不进版本库。** 线上页面永远由 Actions 用源码现场生成，不需要手动提交编译结果。

---

## 2. 内容放在哪里（改站点时查这张表）

| 想改什么 | 改哪个文件 |
| --- | --- |
| 站点标题、作者、头像、简介、社交链接 | `_config.yml`（`author:` 段） |
| 顶部导航菜单 | `_data/navigation.yml` |
| 首页正文 | `_pages/about.md` |
| 简历 | `_pages/cv.md`（数据版：`_data/cv.json`） |
| 论文列表 | `_bibliography/publications.bib`（BibTeX，自动渲染到 `/publications/`） |
| 博客文章 | `_posts/YYYY-MM-DD-标题.md` |
| 草稿（默认不发布） | `_drafts/`，预览时加 `-Drafts` |
| 报告 / 教学 / 作品 / 脚本 | `_talks/`、`_teaching/`、`_portfolio/`、`_scripts/` |
| 头像图片 | `images/profile.png` |
| 论文 PDF、附件 | `files/`（线上地址 `.../files/xxx.pdf`） |
| 配色、版式 | `_sass/`、`assets/css/` |
| 页头、页脚、侧栏组件 | `_includes/` |
| 页面布局 | `_layouts/` |

> 改 `_config.yml` 必须重启预览服务器；其它文件保存即生效。

---

## 3. 首次准备（每台电脑做一次）

前置：Ruby 3.1+（含 Devkit）、Node.js 18+、Git。

```powershell
cd personal-site
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

脚本依次完成：

1. 校验 Ruby / Bundler / Node 版本；
2. 把 Ruby 依赖装进仓库内的 `vendor/bundle`，RubyGems 走清华 TUNA 镜像（只改本机 bundler 配置，**不动 Gemfile**）；
3. 把本仓库的 Git TLS 后端切到 OpenSSL（这台机器的 Windows schannel 会报 `SEC_E_NO_CREDENTIALS`），**保留你原有的代理设置**，并顺便验证能否连上远端；
4. 执行 `bundle install`；
5. 生产模式试构建一次。

安装完成后仓库里会多出 `vendor/`、`.bundle/`、`_site/`——三者都已在 `.gitignore` 中，不会被提交。

> 首次 `bundle install` 需要编译若干原生扩展，可能要几分钟；之后再执行基本秒过。
> 脚本会自行设置 `BUNDLE_USER_CACHE` 等变量，把缓存也固定在仓库内，不写用户目录。

---

## 4. 日常流程：改 → 看 → 校验 → 发

### 4.1 启动本地预览

```powershell
powershell -ExecutionPolicy Bypass -File scripts\dev.ps1
```

- 打开 <http://127.0.0.1:4000>
- 保存 `_posts`、`_pages`、`_sass` 等文件后浏览器自动刷新（LiveReload）
- 预览草稿：加 `-Drafts`
- 换端口：`-Port 4001`
- 退出：`Ctrl+C`
- 端口被占用时脚本会直接告诉你占用的 PID 和换端口命令

### 4.2 发布前校验

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

用**与线上相同的命令**构建（`JEKYLL_ENV=production bundle exec jekyll build`），随后由 `scripts/check-site.mjs` 检查：

- Liquid 渲染报错（有则失败）；
- 站内死链与缺失图片（绝对路径、相对路径都按浏览器规则解析；默认警告，加 `-StrictLinks` 视为失败）；
- 页面数、文件数、总体积。

### 4.3 上传发布

```powershell
powershell -ExecutionPolicy Bypass -File scripts\publish.ps1 -Message "新增 2026 年论文"
```

流程：构建校验 → `git add -A` → commit → `git push origin master` → 打印 Actions 链接。

- 只看这次会提交什么：加 `-DryRun`
- 只提交不推送：加 `-NoPush`
- 跳过构建校验：加 `-SkipBuild`（不推荐）

推送后打开 <https://github.com/Bo-Wang-EM/Bo-Wang-EM.github.io/actions>，绿勾后 1–3 分钟线上生效。

### 4.4 回滚

```powershell
git log --oneline -5           # 找到上一个好版本
git revert <commit>            # 生成反向提交
powershell -ExecutionPolicy Bypass -File scripts\publish.ps1 -Message "回滚到 <commit>"
```

某次构建失败不会弄坏线上：GitHub Pages 会继续提供上一个成功版本。

---

## 5. 脚本一览

| 脚本 | 用途 | 常用参数 |
| --- | --- | --- |
| `scripts/setup.ps1` | 首次准备 / 重装依赖 / 修 Git 设置 | `-GemMirror <url>`、`-SkipGitConfig` |
| `scripts/dev.ps1` | 本地预览服务器 | `-Port 4001`、`-Drafts`、`-NoReload` |
| `scripts/build.ps1` | 生产模式构建 + 产物校验 | `-StrictLinks`、`-SkipChecks` |
| `scripts/publish.ps1` | 构建 → 提交 → 推送 → 触发部署 | `-Message "..."`、`-DryRun`、`-NoPush` |
| `scripts/check-site.mjs` | 产物检查（Liquid 报错 / 死链） | `--strict` |
| `scripts/_common.ps1` | 公共函数（环境变量、命令包装） | — |

> 所有脚本都可以在任意目录用绝对路径调用，它们会自动切换到仓库根目录。

---

## 6. 常见问题

**① `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS`**

Windows 证书子系统在这台机器上取不到凭证，git 用默认的 schannel 后端就连不上 GitHub。修复（只影响本仓库）：

```powershell
git config --local http.sslBackend openssl
```

`setup.ps1` 已自动处理，并会验证远端连通性。

**② 代理**

`~/.gitconfig` 里的 `http.proxy`（`http://127.0.0.1:7897`）本身可用，脚本**不会清空它**。若换了网络导致连不上：

```powershell
git config --local http.proxy http://127.0.0.1:7890   # 改成你的端口
git config --local --unset http.proxy                  # 或者直连
```

**③ `bundle install` 报证书 / 连接失败**

Gemfile 现在用官方源 `https://rubygems.org`（GitHub Actions 能直连）。本机网络访问官方源较慢或不稳，脚本只在本机把它映射到清华 TUNA 镜像，**Gemfile 保持官方源不变，线上构建因此不受影响**。手动设置：

```powershell
bundle config set --local mirror.https://rubygems.org https://mirrors.tuna.tsinghua.edu.cn/rubygems/
```

**④ 关于 `jemoji`（已移除）**

`jemoji` 依赖 `nokogiri`，而 nokogiri 没有 Windows ARM64 预编译包，源码编译会卡在 libiconv 的 `configure`。因此本仓库统一去掉了该插件（`Gemfile` 与 `_config.yml` 相应位置都留了注释）。影响仅限：示例页 `_pages/markdown.md` 里的 `:computer:` 之类不再渲染成图标。想恢复就取消那几行注释（需要先在 ARM64 上能编译 nokogiri）。

**⑤ 端口 4000 被占用**

`dev.ps1` 会打印占用进程；也可以手动：

```powershell
Get-NetTCPConnection -LocalPort 4000 -State Listen | Select-Object OwningProcess
Stop-Process -Id <PID>
```

**⑥ 改 `_config.yml` 没生效**

该文件不参与热重载：`Ctrl+C` 后重启 `dev.ps1`。

**⑦ 首次 `git push` 要求登录**

会弹出 Git Credential Manager 窗口，选 GitHub 授权即可。弹窗不可用时用 Personal Access Token：

```powershell
git push https://<用户名>:<PAT>@github.com/Bo-Wang-EM/Bo-Wang-EM.github.io.git master
```

**⑧ Sass 弃用警告**

主题自带的 `_sass/vendor`（susy、breakpoint）用了旧语法。`_config.yml` 的 `sass.silence_deprecations` 已把这几类静音，不影响产物。

**⑨ 脚本中文乱码**

`.ps1` 文件保存为 **UTF-8 with BOM**（Windows PowerShell 5.1 需要 BOM 才能正确识别中文）。用 VS Code / Notepad 保存时保持 BOM 编码即可。

---

## 7. 速查

```powershell
# 每天开工
powershell -ExecutionPolicy Bypass -File scripts\dev.ps1

# 改完想发
powershell -ExecutionPolicy Bypass -File scripts\build.ps1     # 可选，publish 会自动做
powershell -ExecutionPolicy Bypass -File scripts\publish.ps1 -Message "这次改了什么"

# 依赖坏了，推倒重来
Remove-Item -Recurse -Force vendor,.bundle,_site
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```
