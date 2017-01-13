source 'https://rubygems.org'

ruby '2.3.1'

gem 'rails', '4.2.7.1'
gem 'rails-observers'
gem 'activerecord-session_store'

# Bundle edge Rails instead:
#gem 'rails',     :git => 'git://github.com/rails/rails.git'

gem 'json'

# Supported DBs
gem 'activerecord-nulldb-adapter', group: :nulldb
gem 'mysql2', group: :mysql
gem 'pg', group: :postgres

group :assets do
  gem 'sass-rails' #, github: 'rails/sass-rails'
  gem 'coffee-rails'
  gem 'coffee-script-source'

  gem 'sprockets'

  gem 'uglifier'
  gem 'eco'
end

gem 'autoprefixer-rails'

gem 'doorkeeper'
gem 'oauth2'

gem 'omniauth'
gem 'omniauth-oauth2'
gem 'omniauth-facebook'
gem 'omniauth-github'
gem 'omniauth-gitlab'
gem 'omniauth-google-oauth2'
gem 'omniauth-linkedin-oauth2'
gem 'omniauth-twitter'

gem 'twitter'
gem 'telegramAPI'
gem 'koala'
gem 'mail'
gem 'email_verifier'
gem 'htmlentities'

gem 'mime-types'

gem 'biz'

gem 'delayed_job_active_record'
gem 'daemons'

gem 'simple-rss'

# e. g. on linux we need a javascript execution
gem 'libv8'
gem 'execjs'
gem 'therubyracer'

require 'erb'
require 'yaml'

gem 'net-ldap'

gem 'writeexcel'
gem 'icalendar'
gem 'browser'

# integrations
gem 'slack-notifier'
gem 'clearbit'
gem 'zendesk_api'

# event machine
gem 'eventmachine'
gem 'em-websocket'

gem 'diffy'

# Gems used only for develop/test and not required
# in production environments by default.
group :development, :test do

  gem 'rspec-rails'
  gem 'test-unit'
  gem 'spring'
  gem 'spring-commands-rspec'
  gem 'sqlite3'

  # code coverage
  gem 'simplecov'
  gem 'simplecov-rcov'
  gem 'coveralls',         require: false

  # UI tests w/ Selenium
  gem 'selenium-webdriver'

  # livereload on template changes (html, js, css)
  gem 'guard',             require: false
  gem 'guard-livereload',  require: false
  gem 'rack-livereload'
  gem 'rb-fsevent',        require: false

  # code QA
  gem 'pre-commit'
  gem 'rubocop'
  gem 'coffeelint'

  # changelog generation
  gem 'github_changelog_generator'
end

gem 'puma', group: :puma
gem 'unicorn', group: :unicorn

# load onw gem's
local_gemfile = File.join(File.dirname(__FILE__), 'Gemfile.local')
if File.exist?(local_gemfile)
  eval_gemfile local_gemfile
end
