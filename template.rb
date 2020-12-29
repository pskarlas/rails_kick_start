=begin
Template Name: RailsKickStart
Author: Panagiotis Skarlas 
Author URI: https://github.com/pskarlas
Instructions: $ rails new myapp --database=postgresql --webpack=stimulus -T -m template.rb
=end

def source_paths
  [File.expand_path(File.dirname(__FILE__))]
end

# Gems
def add_gems 
  gem 'view_component', '~> 2.23', '>= 2.23.2', require: "view_component/engine"
  gem 'sidekiq', '~> 6.1', '>= 6.1.2'
  gem 'hiredis', '~> 0.6.3'
  gem 'redis', '~> 4.2', '>= 4.2.5', require: ['redis', 'redis/connection/hiredis']

  gem_group :test, :development do 
    gem 'rspec-rails', '~> 4.0', '>= 4.0.2'
    gem 'letter_opener_web', '~> 1.4'
  end

  gem_group :test do 
    gem 'capybara', '>= 2.15'
    gem 'selenium-webdriver'
    gem 'capybara-screenshot', '~> 1.0', '>= 1.0.25'
    gem 'simplecov', require: false
  end

  gem_group :development do 
    gem 'pry'
    gem 'pry-nav'
    gem 'rubocop-rails'
    gem 'rubocop-performance', '~> 1.9', '>= 1.9.1'
    gem 'solargraph', '~> 0.40.1'
  end
end

# Helpers
def setup_foreman
  procfile_content = <<~YML
    web: bin/rails s -p 3000
    webpacker: ./bin/webpack-dev-server
    worker: bundle exec sidekiq -C config/sidekiq.yml
  YML

  add_file "Procfile", procfile_content
end

def setup_rubocop
  rubocop_config = <<~EOS
    require: rubocop-rails
    require: rubocop-performance
  EOS
  add_file ".rubocop.yml", rubocop_config
end

def setup_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"
  sidekiq_yml = <<~YML
  :concurrency: 10 
  :queues:
    - [critical, 2]
    - mailers
    - default
  YML
  add_file "config/sidekiq.yml", sidekiq_yml 

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<~RUBY
    mount Sidekiq::Web => '/sidekiq'
  RUBY

  insert_into_file "config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n"
end

def setup_test_gems
  rails_command "generate rspec:install"
  append_to_file ".rspec", '--format documentation'
  spec_requires = <<~EOS
    #frozen_string_literal: true
    require 'capybara/rspec'
    require 'capybara-screenshot/rspec'
    require 'capybara-screenshot'
    require 'simplecov'\n
    Capybara.javascript_driver = :selenium_chrome
    Capybara.asset_host = 'http://localhost:3000'
    Capybara::Screenshot.append_timestamp = false\n
    Capybara::Screenshot.register_filename_prefix_formatter(:rspec) do |example|
      \"screenshot_\#{example.description.gsub(' ', '-').gsub(/^.*\\/spec\\//,'')}\"
    end
    SimpleCov.start
  EOS
  prepend_to_file "spec/spec_helper.rb", "#{spec_requires}"
  append_to_file ".gitignore", 'coverage'
end

def setup_letter_opener 
  content = <<~EOS
    mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  EOS
  insert_into_file "config/routes.rb", content, after: "Rails.application.routes.draw do\n"
  environment "config.action_mailer.delivery_method = :letter_opener", env: 'development'
  environment "config.action_mailer.perform_deliveries = true", env: 'development'
end

def add_example_view_component
  rails_command "g component Example title content"
end

def setup_tailwind
  # Until PostCSS 8 ships with Webpacker/Rails we need to run this compatability version
  # See: https://tailwindcss.com/docs/installation#post-css-7-compatibility-build
  run "yarn add tailwindcss@npm:@tailwindcss/postcss7-compat postcss@^7 autoprefixer@^9"
  run "mkdir -p app/javascript/stylesheets"
  css_content = <<~EOS 
    @import "tailwindcss/base";
    @import "tailwindcss/components";
    @import "tailwindcss/utilities";
  EOS
  
  tailwind_config = <<~EOS
  module.exports = {
    purge: [
      './app/**/*.html.erb',
      './app/helpers/**/*.rb',
      './app/javascript/**/*.js',
      './app/javascript/**/*.vue',
    ],
    theme: {
      extend: {
        colors: {
         
        },
        height: {
          '18': '4.625rem'
        },
        maxWidth: {
          '7xl': '80rem',
          '8xl': '88rem',
          '9xl': '96rem'
        },
        borderRadius: {
          xl: '0.8rem'
        },
      },
    },
    variants: {
      borderWidth: ['responsive', 'hover', 'focus', 'even', 'first'],
      borderColor: ['responsive', 'hover', 'focus', 'active', 'group-hover'],
      opacity: ['active', 'hover', 'group-hover'],
    },
    plugins: [
      
    ],
   
  }
  EOS

  add_file "app/javascript/stylesheets/application.scss",  css_content
  add_file "app/javascript/stylesheets/tailwind.config.js", tailwind_config 

  append_to_file("app/javascript/packs/application.js", 'import "stylesheets/application"')
  inject_into_file("./postcss.config.js", "\n    require('tailwindcss')('./app/javascript/stylesheets/tailwind.config.js'),", after: "plugins: [")

  # Remove Application CSS
  remove_file "app/assets/stylesheets/application.css"
  gsub_file('app/views/layouts/application.html.erb', /<%= stylesheet_link_tag 'application', media: 'all' %>/, '<%= stylesheet_pack_tag \'application\', media: \'all\' %>')
end

# Begin Setup
source_paths()
# Add gems to Gemfile
add_gems()

after_bundle do
  # Weird things happen when spring is running
  run "spring stop"
  setup_foreman()
  setup_rubocop()
  setup_sidekiq()
  setup_test_gems()
  add_example_view_component()
  setup_tailwind()
  setup_letter_opener()
  run "spring start"

  # Migrate
  rails_command "db:prepare"

  git :init
  git add: "."
  git commit: %Q{ -m "Initial commit" }
  
  say
  say "Kickoff app successfully created! 👍", :green
  say
  say "Switch to your app by running:"
  say "$ cd #{app_name}", :yellow
  say
  say "Foreman shouldn't be bundled in as a dependency. So install it now by running"
  say "gem install foreman", :yellow

  say "Start the app by running:"
  say "foreman start"
end
