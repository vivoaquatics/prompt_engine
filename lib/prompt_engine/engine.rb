module PromptEngine
  class Engine < ::Rails::Engine
    isolate_namespace PromptEngine

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end

    # Ensure services and clients directories are in the autoload paths
    config.autoload_paths += %W[#{config.root}/app/services]
    config.autoload_paths += %W[#{config.root}/app/clients]

    # IMPORTANT: Migrations are NOT automatically loaded!
    # Users must explicitly install migrations using:
    #   bin/rails prompt_engine:install:migrations
    #
    # This ensures host applications have full control over when
    # engine migrations are added to their codebase.
    #
    # The following initializer is intentionally disabled:
    # initializer :append_migrations do |app|
    #   unless app.root.to_s.match?(root.to_s) || app.root.to_s.include?('spec/dummy')
    #     config.paths["db/migrate"].expanded.each do |expanded_path|
    #       app.config.paths["db/migrate"] << expanded_path
    #     end
    #   end
    # end

    # Define the controller hook for authentication customization
    initializer "prompt_engine.controller_hook" do
      ActiveSupport.on_load(:prompt_engine_application_controller) do
        # This hook allows host applications to add authentication
        # and other controller-level customizations
      end
    end

    # Defense in depth: the playground still accepts an optional api_key param for
    # hosts that have not stored one. This guard only protects hosts that append to
    # the default filter list; a host that fully *replaces* config.filter_parameters
    # (e.g. `config.filter_parameters = [:only_this]`) after this initializer runs
    # will still not redact :api_key.
    initializer "prompt_engine.filter_parameters" do |app|
      app.config.filter_parameters << :api_key unless app.config.filter_parameters.include?(:api_key)
    end

    # Allow middleware to be added for authentication
    # Example: PromptEngine::Engine.middleware.use(Rack::Auth::Basic) { ... }
  end
end
