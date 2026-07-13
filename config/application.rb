require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SeloDigital
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # siscartd is a Ceará (TJCE) system; "timestamp without time zone" columns like
    # sd_atosPraticados.data_registro are written in local Brazil time (UTC-3, no DST)
    # by external processes, not UTC. default_timezone: :local makes ActiveRecord
    # interpret those naive timestamps correctly instead of mislabeling them UTC.
    config.time_zone = "Brasilia"
    config.active_record.default_timezone = :local
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
