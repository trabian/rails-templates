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

  gem "trabian_cms", "5.0.13", :git => "git@github.com:trabian/trabian_cms.git"

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

  require File.join(File.dirname(__FILE__), '..', "vendor", "bundler_gems", "environment")

  gem_root = Dir[File.join(File.dirname(__FILE__), '..', 'gems', '*')].detect do |filename|
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