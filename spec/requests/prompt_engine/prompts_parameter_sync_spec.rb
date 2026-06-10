require "rails_helper"

module PromptEngine
  RSpec.describe "Prompts parameter syncing on update", type: :request do
    # Regression: editing a prompt to add a new variable used to fail with
    # "Name has already been taken" because the form emitted parameter `id`
    # fields twice (the JS-built #parameters-list keyed by detection order, and
    # a `fields_for :parameters` block keyed by position order). Rack merged
    # them by index, pairing an existing param's id with a different param's
    # name whenever the two orders diverged. The duplicate `fields_for` block
    # has been removed; the JS list is now the single source of truth.

    def form_post(path, pairs)
      body = pairs.map { |k, v| "#{CGI.escape(k)}=#{CGI.escape(v.to_s)}" }.join("&")
      patch path, params: body,
        headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    end

    it "adds a new variable when detection order diverges from position order" do
      prompt = Prompt.create!(
        name: "Repro", slug: "repro",
        content: "Hello {{name}}",
        system_message: "Schema {{input_schema}}"
      )
      name_p   = prompt.parameters.find_by!(name: "name")
      schema_p = prompt.parameters.find_by!(name: "input_schema")

      # User reorders content to put {{input_schema}} first and adds {{tone}}.
      # The fixed form emits ONLY the JS-built list, in detection order:
      pairs = [
        [ "prompt[name]", "Repro" ],
        [ "prompt[slug]", "repro" ],
        [ "prompt[content]", "{{input_schema}} Hello {{name}} {{tone}}" ],
        [ "prompt[system_message]", "Schema" ],
        [ "prompt[parameters_attributes][0][name]", "input_schema" ],
        [ "prompt[parameters_attributes][0][id]", schema_p.id ],
        [ "prompt[parameters_attributes][0][parameter_type]", "string" ],
        [ "prompt[parameters_attributes][0][required]", "1" ],
        [ "prompt[parameters_attributes][1][name]", "name" ],
        [ "prompt[parameters_attributes][1][id]", name_p.id ],
        [ "prompt[parameters_attributes][1][parameter_type]", "string" ],
        [ "prompt[parameters_attributes][1][required]", "1" ],
        [ "prompt[parameters_attributes][2][name]", "tone" ],
        [ "prompt[parameters_attributes][2][parameter_type]", "string" ],
        [ "prompt[parameters_attributes][2][required]", "1" ]
      ]

      form_post prompt_engine.prompt_path(prompt), pairs

      expect(response).to have_http_status(:found)
      expect(prompt.reload.parameters.pluck(:name).sort).to eq(%w[input_schema name tone])
    end

    it "syncs parameters when a variable is added only to the system_message" do
      prompt = Prompt.create!(
        name: "SysOnly", slug: "sys-only",
        content: "Hello {{name}}",
        system_message: "You are helpful"
      )

      # Programmatic update (no nested attributes) -- the model's own sync must
      # pick up a variable added solely to the system_message.
      prompt.update!(system_message: "You are helpful. Schema: {{input_schema}}")

      expect(prompt.reload.parameters.pluck(:name).sort).to eq(%w[input_schema name])
    end

    it "removes a parameter when its variable is deleted from the system_message" do
      prompt = Prompt.create!(
        name: "SysRemove", slug: "sys-remove",
        content: "Hello {{name}}",
        system_message: "Schema: {{input_schema}}"
      )
      expect(prompt.parameters.pluck(:name).sort).to eq(%w[input_schema name])

      prompt.update!(system_message: "No variables here")

      expect(prompt.reload.parameters.pluck(:name)).to eq(%w[name])
    end
  end
end
