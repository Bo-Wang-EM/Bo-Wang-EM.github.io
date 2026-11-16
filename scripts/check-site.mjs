#!/usr/bin/env node
/**
 * 校验 Jekyll 构建产物（_site）。
 *
 * 检查项：
 *   1. Liquid 渲染残留（"Liquid error/Exception"、"{%" 未解析）—— 视为失败；
 *   2. 站内链接与静态资源是否存在 —— 默认警告，加 --strict 视为失败；
 *   3. 输出页面数量与体积概览。
 *
 * 用法：
 *   node scripts/check-site.mjs _site
 *   node scripts/check-site.mjs _site --strict
 */

import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';

const argv = process.argv.slice(2);
const strict = argv.includes('--strict');
const target = argv.find((a) => !a.startsWith('--')) ?? '_site';
const siteDir = path.resolve(process.cwd(), target);

const SKIP_SCHEME = /^(https?:|mailto:|tel:|javascript:|data:|ftp:|sms:|#|\/\/)/i;
const LIQUID_ERROR = /Liquid (error|Exception|syntax error)|Liquid\s+Warning/i;

async function walk(dir, out = []) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      // 跳过 Jekyll 自带的 404 相关目录与源码目录
      if (entry.name === '.git' || entry.name === 'node_modules') continue;
      await walk(full, out);
    } else {
      out.push(full);
    }
  }
  return out;
}

function exists(target) {
  return stat(target).then(
    (s) => s.isFile(),
    () => false,
  );
}

/**
 * 把链接映射为 _site 下可能对应的文件。
 * "/xxx" 从站点根算；"xxx" 相对当前页面所在目录算（与浏览器一致）。
 */
function candidatesFor(urlPath, pageFile) {
  const clean = decodeURIComponent(urlPath.split('?')[0].split('#')[0]);
  if (clean === '' || clean === '/') return [path.join(siteDir, 'index.html')];

  const base = clean.startsWith('/')
    ? path.join(siteDir, clean.replace(/^\/+/, ''))
    : path.resolve(path.dirname(pageFile), clean);

  // 防止 ../ 逃出 _site
  if (!base.startsWith(siteDir)) return [];

  if (clean.endsWith('/')) return [path.join(base, 'index.html')];

  const list = [base, `${base}.html`, path.join(base, 'index.html')];
  return list;
}

async function main() {
  let dirStat;
  try {
    dirStat = await stat(siteDir);
  } catch {
    console.error(`[X] 找不到构建目录：${siteDir}`);
    process.exit(2);
  }
  if (!dirStat.isDirectory()) {
    console.error(`[X] 不是目录：${siteDir}`);
    process.exit(2);
  }

  const files = await walk(siteDir);
  const htmlFiles = files.filter((f) => f.endsWith('.html'));
  if (htmlFiles.length === 0) {
    console.error(`[X] ${siteDir} 里没有 HTML，构建可能失败`);
    process.exit(2);
  }

  const liquidErrors = [];
  const brokenLinks = new Map(); // 目标 -> [引用页面]
  let linkCount = 0;

  for (const file of htmlFiles) {
    const html = await readFile(file, 'utf8');
    const relFile = path.relative(siteDir, file).replaceAll('\\', '/');

    if (LIQUID_ERROR.test(html)) {
      const match = html.match(LIQUID_ERROR);
      liquidErrors.push(`${relFile}: ${match?.[0] ?? 'Liquid 报错'}`);
    }

    const attrs = [...html.matchAll(/\s(?:href|src)\s*=\s*"([^"]*)"/gi)];
    for (const [, raw] of attrs) {
      const url = raw.trim();
      if (!url || SKIP_SCHEME.test(url) || url.includes('{{') || url.includes('{%')) continue;
      linkCount += 1;
      const candidates = candidatesFor(url, file);
      let ok = false;
      for (const candidate of candidates) {
        if (await exists(candidate)) {
          ok = true;
          break;
        }
      }
      if (!ok) {
        const key = url;
        if (!brokenLinks.has(key)) brokenLinks.set(key, new Set());
        brokenLinks.get(key).add(relFile);
      }
    }
  }

  const totalBytes = (await Promise.all(files.map((f) => stat(f)))).reduce((n, s) => n + s.size, 0);

  console.log('');
  console.log(`产物目录：${path.relative(process.cwd(), siteDir) || '.'}`);
  console.log(`页面：${htmlFiles.length} 个 HTML，共 ${files.length} 个文件，${(totalBytes / 1024 / 1024).toFixed(1)} MB`);
  console.log(`检查了 ${linkCount} 个站内链接/资源引用`);

  let failed = false;

  if (liquidErrors.length) {
    failed = true;
    console.log('');
    console.log(`[X] Liquid 渲染失败 ${liquidErrors.length} 处：`);
    for (const item of liquidErrors.slice(0, 20)) console.log(`    - ${item}`);
  }

  if (brokenLinks.size) {
    console.log('');
    const label = strict ? '[X]' : '[!]';
    console.log(`${label} 站内死链 ${brokenLinks.size} 个：`);
    const entries = [...brokenLinks.entries()].slice(0, 20);
    for (const [url, pages] of entries) {
      const from = [...pages].slice(0, 2).join(', ');
      console.log(`    - ${url}  <- ${from}${pages.size > 2 ? ` 等 ${pages.size} 处` : ''}`);
    }
    if (brokenLinks.size > 20) console.log(`    ...另有 ${brokenLinks.size - 20} 个`);
    if (strict) failed = true;
  }

  if (!liquidErrors.length && !brokenLinks.size) {
    console.log('');
    console.log('[OK] 产物校验通过：无 Liquid 报错、无站内死链');
    return;
  }

  if (!failed) {
    console.log('');
    console.log('[OK] 无 Liquid 报错（死链仅警告，可用 --strict 提升为失败）');
  }

  process.exit(failed ? 1 : 0);
}

main().catch((error) => {
  console.error('[X] 校验脚本异常：', error);
  process.exit(2);
});
