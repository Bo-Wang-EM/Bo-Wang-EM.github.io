source 'https://gems.ruby-china.com'

group :jekyll_plugins do
  gem 'jekyll'
  gem 'jekyll-feed'
  gem 'jekyll-sitemap'
  gem 'jekyll-redirect-from'
  # jemoji 依赖 nokogiri；Windows ARM64 没有预编译包，源码编译会卡在 libiconv/configure。
  # 站点内容只在一篇示例页里提到 emoji，因此本地与线上统一不启用该插件。
  # 如需恢复：取消下面一行注释，并同步 _config.yml 的 plugins / whitelist。
  # gem 'jemoji'
  gem 'webrick', '~> 1.8'
  gem 'jekyll-scholar'
  gem 'jekyll-sass-converter'
  gem 'jekyll-gist'
  gem 'jekyll-paginate'
end

#gem 'github-pages'
gem 'connection_pool', '2.5.0'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]