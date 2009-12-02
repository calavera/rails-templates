require 'rubygems'

run 'gem source --add http://rc-gems.appspot.com'

gems_index = Gem::SourceIndex.from_gems_in('local')

unless gems_index.find_name('appengine-sdk', '>=1.2.8')
  system('curl -C - -O http://appengine-jruby.googlecode.com/files/appengine-sdk-1.2.8.gem')
  run 'gem install appengine-sdk-1.2.8.gem', :sudo => true
end

unless gems_index.find_name('google-appengine', '>=0.0.6')
  run 'gem install google-appengine', :sudo => true
end

info_controller = %s{class Rails::InfoController < ActionController::Base
  def properties
    info = [['Ruby version', "#{RUBY_VERSION} (#{RUBY_PLATFORM})"]]
    if defined? Gem::RubyGemsVersion
      info << ['RubyGems version', Gem::RubyGemsVersion]
    else
      info << ['RubyGems','disabled']
    end
    info << ['Rack version', Rack.release]
    # get versions from rails frameworks 
    info << ['Rails version', Rails::VERSION::STRING]
    frameworks = %w{action_pack active_model active_support}
    frameworks.unshift('active_record') if defined? ActiveRecord
    frameworks.push('active_resource')  if defined? ActiveResource
    frameworks.push('action_mailer')    if defined? ActionMailer
    frameworks.each do |f|
      require "#{f}/version"
      info << [ "#{f.titlecase} version",
                "#{f.classify}::VERSION::STRING".constantize]
    end
    info << ['DataMapper version', DataMapper::VERSION] if defined? DataMapper
    info << ['Environment', RAILS_ENV]
    # get versions from jruby environment
    if defined?(JRuby::Rack::VERSION)
      info << ['JRuby version', JRUBY_VERSION]
      info << ['JRuby-Rack version', JRuby::Rack::VERSION]
    end
    # get information from app engine
    if defined?(AppEngine::ApiProxy)
      require 'appengine-apis' # for VERSION
      env = AppEngine::ApiProxy.current_environment
      ver = env.getVersionId[0,env.getVersionId.rindex(".")]
      info << ['AppEngine APIs version', AppEngine::VERSION]
      info << ['Auth domain', env.getAuthDomain]
      info << ['Application id:version', env.getAppId + ":#{ver}"]
    end
    # render as an HTML table
    html = "<table><tbody>"
    info.each { |k,v| html += "<tr><td>#{k}</td><td>#{v}</td></tr>" }
    html += "</tbody></table>"
    render :text => html
  end
end}

file 'app/controllers/rails/info_controller.rb', info_controller

file 'config.ru', <<-CONFIG
require 'appengine-rack'
AppEngine::Rack.configure_app(
    :application => 'application-id',
    :precompilation_enabled => true,
    :version => 1)

AppEngine::Rack.app.resource_files.exclude :rails_excludes
AppEngine::Rack.app.resource_files.exclude 'bin/**'
ENV['RAILS_ENV'] = AppEngine::Rack.environment

# Require your environment file to bootstrap Rails
require ::File.expand_path('../config/environment',  __FILE__)

# Dispatch the request
run RailsApp
CONFIG

file 'Gemfile', <<-GEMFILE
# Critical default settings:
disable_system_gems
disable_rubygems
bundle_path ".gems/bundler_gems"
 
clear_sources
source 'http://gemcutter.org'
source 'http://rc-gems.appspot.com' # WARNING: prerelease repo

# List gems to bundle here:
gem "rails", "3.0.pre", :git => "git://github.com/rails/rails.git"
gem "arel",             :git => "git://github.com/rails/arel.git"
gem "i18n"
gem "dm-appengine"
gem 'dm-timestamps'
gem 'dm-validations'
GEMFILE

initializer 'notifications.rb', <<-NOTIFICATIONS
# Set our own default Notifier
module ActiveSupport::Notifications
  self.notifier = Notifier.new(Fanout.new(true))
end
NOTIFICATIONS

file 'config/boot.rb', <<-BOOT
# replace this file with the following
require 'fileutils'
FileUtils = FileUtils::NoWrite if ENV['RAILS_ENV'].eql? 'production'
$LOAD_PATH << 'lib'
require 'rails'
BOOT

application_init = "config.time_zone = 'UTC'

  # Set DataMapper to use dm-appengine adapter
  require 'dm-core'
  require 'dm-timestamps'
  require 'dm-validations'
  DataMapper.setup(:default, 'appengine://auto')
  # Set Logger from appengine-apis, all environments
  require 'appengine-apis/logger'
  config.logger = AppEngine::Logger.new
  # Skip frameworks you're not going to use.
  config.frameworks -= [ :active_record, :active_resource, :action_mailer ]"

config_file_name = File.exist?('config/application.rb') ? 'application' : 'environment'

environment = `cat config/#{config_file_name}.rb`
environment.gsub!(/config\.time_zone = 'UTC'/, application_init)

system("echo \"#{environment}\" > config/#{config_file_name}.rb")

run 'appcfg.rb bundle .'