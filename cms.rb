require 'rubygems'
require 'bundler'

CMS_VERSION='5.3.18'

title = ENV['CMS_TITLE'] || ask("What's the title of the site?")

# solr_port = ENV['CMS_SOLR_PORT'] || ask("What's the starting port for the SOLR server?")
# seed = ENV['CMS_SEED_DB'] || ask("Do you want to create and seed the database (yN)?")
db_user = ENV['CMS_DB_USER'] || ask("What's your database username?")
db_pass = ENV['CMS_DB_PASSWORD'] || ask("What's your database password?")
# database = ENV['CMS_DATABASE'] || ask("Which database would you like to use? (mysql|sqlite3)")

seed = 'y'
database = 'mysql'
solr_port = 8991

# Cleanup
run "rm public/index.html"
run "rm public/images/rails.png"
run "rm public/javascripts/{application,controls,dragdrop,effects,prototype}.js"
run "rm -Rf test"

# Make sure this is near the top so that app/javascripts is available for less_routes.js generation
file 'app/javascripts/public/application.js', <<-FILE
//= require <jquery>

;$(function() {});
FILE


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

file 'Gemfile', %{
source :gemcutter
source 'http://gems.github.com'

git "git@github.com:trabian/trabian_cms.git", :tag => "v#{CMS_VERSION}"
gem "trabian_cms"

group :test do
  gem 'rspec', '1.2.8'
  gem 'rspec-rails', '1.2.7.1'
  gem 'carlosbrando-remarkable', '2.3.1'
  gem 'webrat', '0.4.4'
  gem 'cucumber', '0.3.94'
  gem 'factory_girl', '1.2.2'
end
}.strip

run 'bundle install'

file 'config/preinitializer.rb', %{

class Pathname  
  def empty?  
    to_s.empty?  
  end
end

begin
  require File.expand_path('../../.bundle/environment', __FILE__)
rescue LoadError
  require 'rubygems'
  require 'bundler'
  Bundler.setup
end

cms_lib_dir = $LOAD_PATH.detect do |filename|
  filename.match /trabian_cms[^_]/
end

gem_root = cms_lib_dir.gsub('/lib', '')

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

gsub_file 'config/boot.rb', 'Rails.boot!', %{
class Rails::Boot
  def run
    load_initializer

    Rails::Initializer.class_eval do
      def load_gems
        @bundler_loaded ||= Bundler.require :default, Rails.env
      end
    end

    Rails::Initializer.run(:set_load_path)

  end

end

Rails.boot!

class Rails::Plugin::GemLocator
  # find the original that we patch in rails/lib/rails/plugin/locator.rb:80
  def plugins
    specs = begin
      Bundler::SPECS
    rescue
      Bundler.load.send(:specs_for, [:default, Rails.env])
    end
    specs    += Gem.loaded_specs.values.select do |spec|
      spec.loaded_from && # prune stubs
        # File.exist?(File.join(spec.full_gem_path, "rails", "init.rb"))
        (File.exist?(File.join(spec.full_gem_path, "rails", "init.rb")) || File.exist?(File.join(spec.full_gem_path, "init.rb")))
    end
    specs.compact!

    require "rubygems/dependency_list"

    deps = Gem::DependencyList.new
    deps.add(*specs) unless specs.empty?

    deps.dependency_order.collect do |spec|
      Rails::GemPlugin.new(spec, nil)
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

  config.load_paths += %W( \#{RAILS_ROOT}/app/panels \#{RAILS_ROOT}/app/presenters \#{RAILS_ROOT}/app/middleware )

  \# config.action_controller.page_cache_directory = RAILS_ROOT + "/public/cache/"

  config.middleware.use(Rack::Cache, :verbose => true, :metastore => "file:\#{CMS.metastore}", :entitystore => "file:\#{CMS.entitystore}")

  config.time_zone = 'Central Time (US & Canada)'

end

# Used by uploadify
ActionController::Dispatcher.middleware.insert_before(
  ActionController::Session::CookieStore,
  FlashSessionCookieMiddleware,
  ActionController::Base.session_options[:key]
)

CMS.start

}

file 'app/controllers/application_controller.rb', %{
# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include CMS::ApplicationController
  
  # include any custom actions below this line
end
}

file 'config/routes.rb', %{
ActionController::Routing::Routes.draw do |map|
  map.section '*path', :controller => 'sections', :action => 'show'
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

}

# Sunspot
#file 'config/sunspot.yml', %{
#  production:
#    solr:
#      hostname: localhost
#      port: #{solr_port.to_i + 2}
#      log_level: WARNING
#
#  development:
#    solr:
#      hostname: localhost
#      port: #{solr_port.to_i + 1}
#      log_level: INFO
#
#  test:
#    solr:
#      hostname: localhost
#      port: #{solr_port}
#      log_level: WARNING
#}
#
#rake "sunspot:solr:start"

# Database
if (database == 'mysql')
  app_name = File.basename(@root)

  file 'config/database.yml', <<-CODE
development: &base
  adapter: mysql
  host: localhost
  username: #{db_user}
  password: #{db_pass}
  database: #{app_name}

test:
  <<: *base
  database: #{app_name}_test

production:
  <<: *base
  database: #{app_name}
CODE
end

if seed == "y"

  rake "db:create"

  # Seed database

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
    s.email = "admin@trabian.com"
    s.password = s.password_confirmation = "password"
  end

  admin = User.find(1)
  admin.has_role('full_admin')
  FILE

  rake "cms:migrate:copy"
  rake "db:migrate"
  rake "db:seed"

  puts "A user has been created with a login of 'admin@trabian.com' and a password of 'password'"

end

rake 'sprockets:install_assets'

git :init

git :add => "."

git :commit => "-a -m 'Initial commit'"