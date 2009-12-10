CMS_VERSION='5.0.14'

# Cleanup
run "rm public/index.html"
run "rm public/images/rails.png"
run "rm -Rf test"

# Git ignore
file '.gitignore', %{
.DS_Store
log/*.log
tmp/**/*
tmp/*
config/database.yml
db/*.sqlite3
public/stylesheets/compiled/**
public/sprockets.js
public/assets/**/*
public/system
public/cache
solr/**
**/*.swp
*.swp
gems/*
!gems/cache
!gems/bundler
}.strip

# Install Bundler
inside 'gems/bundler' do
  run 'git init'
  run 'git pull --depth 1 git://github.com/wycats/bundler.git'
  run 'rm -rf .git .gitignore'
end

file 'script/bundle', %{
#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), "..", "gems/bundler/lib"))
require 'rubygems'
require 'rubygems/command'
require 'bundler'
require 'bundler/commands/bundle_command'
Gem::Commands::BundleCommand.new.invoke(*ARGV)
}.strip

run 'chmod +x script/bundle'

file 'Gemfile', %{
  bundle_path 'gems'
  bin_path "bin/gems/"
  disable_system_gems
  clear_sources

  source 'http://gemcutter.org'
  source 'http://gems.github.com'

  gem "trabian_cms", "#{CMS_VERSION}", :git => "git@github.com:trabian/trabian_cms.git"

  only :test do
    gem 'rspec', '1.2.8'
    gem 'rspec-rails', '1.2.7.1'
    gem 'carlosbrando-remarkable', '2.3.1'
    gem 'webrat', '0.4.4'
    gem 'cucumber', '0.3.94'
    gem 'factory_girl', '1.2.2'
  end
}.strip

run "mkdir -p bin/gems gems"

puts "Preparing to install bundled gems.  This may take a while."

run 'script/bundle'

file 'config/preinitializer.rb', %{

require File.join(File.dirname(__FILE__), '..', "gems", "environment")

gem_root = Dir[File.join(File.dirname(__FILE__), '..', 'gems', 'dirs', '*')].detect do |filename|
  File.basename(filename).match /^trabian_cms/
end

CMS_ROOT = gem_root
$LOAD_PATH << File.join(gem_root, 'lib')
require 'trabian_cms'

# Authorization plugin for role based access control
# You can override default authorization system constants here.

# Can be 'object roles' or 'hardwired'
AUTHORIZATION_MIXIN = "object roles"

# NOTE : If you use modular controllers like '/admin/products' be sure 
# to redirect to something like '/sessions' controller (with a leading slash)
# as shown in the example below or you will not get redirected properly
#
# This can be set to a hash or to an explicit path like '/login'
#
LOGIN_REQUIRED_REDIRECTION = { :controller => 'admin/overview', :action => 'index' }
PERMISSION_DENIED_REDIRECTION = { :controller => 'admin/overview', :action => 'index' }

# The method your auth scheme uses to store the location to redirect back to 
STORE_LOCATION_METHOD = :store_location

}.strip

gsub_file 'config/boot.rb', '# All that for this:', %{
class Rails::Boot
  def run
    load_initializer
    extend_environment
    Rails::Initializer.run(:set_load_path)
  end

  def extend_environment
    Rails::Initializer.class_eval do
      old_load = instance_method(:load_environment)
      define_method(:load_environment) do
        Bundler.require_env RAILS_ENV
        old_load.bind(self).call
      end
    end
  end
end
}

file 'config/environment.rb', %{
# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '2.3.4' unless defined? RAILS_GEM_VERSION

require 'rubygems'
gem 'rack-cache'
require 'rack/cache'

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

Rails::Initializer.run do |config|

  config.plugin_paths << File.join(CMS_ROOT, 'vendor', 'plugins')

  config.load_paths += %W( #{RAILS_ROOT}/app/panels #{RAILS_ROOT}/app/presenters #{RAILS_ROOT}/app/middleware )

  config.action_controller.page_cache_directory = RAILS_ROOT + "/public/cache/"

  config.middleware.use(Rack::Cache, :verbose => true, :metastore => "file:#{CMS.metastore}", :entitystore => "file:#{CMS.entitystore}")

  config.time_zone = 'Central Time (US & Canada)'

end

Gem.loaded_specs.values.each do |spec|
  returning File.expand_path("init.rb", spec.full_gem_path) do |init_path|
    require init_path if File.exists?(init_path)
  end
end
}

# Rakefile
file 'Rakefile', %{
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require(File.join(File.dirname(__FILE__), 'config', 'boot'))

require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'

require 'tasks/rails'
require 'tasks/cms'

require CMS.root.join('vendor', 'plugins', 'sunspot_rails', 'lib', 'sunspot', 'rails', 'tasks')
}

# Database
# database = ENV['CMS_DATABASE'] || ask("Which database would you like to use? (mysql|sqlite3)")
database = 'mysql'

if (database == 'mysql')
  app_name = File.basename(@root)

  db_user = ENV['CMS_DB_USER'] || ask("What's your database username?")
  db_pass = ENV['CMS_DB_PASSWORD'] || ask("What's your database password?")

  file 'config/database.yml', <<-CODE
development: &base
  adapter: mysql
  host: localhost
  username: #{db_user}
  password: #{db_pass}
  database: cms_#{app_name}

test:
  <<: *base
  database: cms_#{app_name}_test

production:
  <<: *base
  database: cms_#{app_name}
CODE
end

seed = ENV['CMS_SEED_DB'] || ask("Do you want to create and seed the database (yN)?")

if seed == "y"

  rake "db:create"

  # Seed database
  title = ENV['CMS_TITLE'] || ask("What's the title of the site?")

  file 'db/fixtures/settings.rb', <<-FILE
  Setting.seed do |s|
    s.name = 'title'
    s.value = "#{title}"
  end
  FILE

  file 'db/fixtures/sections.rb', <<-FILE
  Section.seed do |s|
    s.content_id = 1
    s.name = "Home"
  end

  Content.seed do |c|
  end
  FILE

  file 'db/fixtures/users.rb', <<-FILE
  User.seed(:login) do |s|
    s.id = 1
    s.name = "Admin"
    s.login = "admin"
    s.email = "admin@trabian.com"
    s.password = s.password_confirmation = "admin"
  end

  admin = User.find(1)
  admin.has_role('full_admin')
  FILE

  rake "cms:migrate:copy"
  rake "db:migrate"
  rake "db:seed"

  puts "A user has been created with a login of 'admin' and a password of 'admin'"

end

# Javascript
file 'config/sprockets.yml', <<-FILE
:default:
  :asset_root: public
  :load_path:
    - app/javascripts/public
    - vendor/sprockets/*/src
    - vendor/plugins/*/javascripts
    - vendor/gems/*/app/javascripts
    - <%= "\#{CMS.root.expand_path}/vendor/sprockets/*/src" %>
  :source_files:
    - app/javascripts/public/application.js
    - app/javascripts/public/**/*.js

:cms:
  :asset_root: public
  :root: <%= CMS.root.expand_path %>
  :load_path:
    - app/javascripts
    - vendor/sprockets/*/src
    - vendor/plugins/*/javascripts
    - <%= RAILS_ROOT %>/app/javascripts
  :source_files:
    - app/javascripts/application.js
    - app/javascripts/**/*.js
    - <%= RAILS_ROOT %>/app/javascripts/cms/extend.js  
  
FILE

file 'app/javascripts/application.js', <<-FILE
//= require <jquery>

;$(function() {});
FILE

rake 'sprockets:install_assets'