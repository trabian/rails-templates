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