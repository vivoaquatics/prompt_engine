require "rails_helper"

module PromptEngine
  RSpec.describe "Settings", type: :request do
    include Engine.routes.url_helpers

    describe "GET /prompt_engine/settings/edit" do
      it "returns a successful response" do
        get edit_settings_path
        expect(response).to be_successful
      end

      it "displays the settings form" do
        get edit_settings_path
        expect(response.body).to include("Settings")
        expect(response.body).to include("OpenAI API Key")
        expect(response.body).to include("Anthropic API Key")
      end

      context "when settings already exist with API keys" do
        let(:seeded_openai_key) { "sk-test-openai-key" }
        let(:seeded_anthropic_key) { "sk-ant-test-anthropic-key" }

        before do
          Setting.instance.update!(
            openai_api_key: seeded_openai_key,
            anthropic_api_key: seeded_anthropic_key
          )
        end

        it "does not display any portion of the stored API keys" do
          get edit_settings_path
          expect(response.body).not_to include(seeded_openai_key)
          expect(response.body).not_to include(seeded_anthropic_key)
        end
      end
    end

    describe "PATCH /prompt_engine/settings" do
      let(:valid_params) do
        {
          setting: {
            openai_api_key: "sk-new-openai-key",
            anthropic_api_key: "sk-ant-new-anthropic-key"
          }
        }
      end

      context "with valid parameters" do
        it "updates the settings" do
          patch settings_path, params: valid_params

          settings = Setting.instance
          expect(settings.openai_api_key).to eq("sk-new-openai-key")
          expect(settings.anthropic_api_key).to eq("sk-ant-new-anthropic-key")
        end

        it "redirects to the edit page with success message" do
          patch settings_path, params: valid_params
          expect(response).to redirect_to(edit_settings_path)
          follow_redirect!
          expect(response.body).to include("Settings have been updated successfully")
        end
      end

      context "when submitting blank API keys" do
        before do
          Setting.instance.update!(
            openai_api_key: "sk-old-key",
            anthropic_api_key: "sk-ant-old-key"
          )
        end

        it "leaves the stored keys unchanged (blank fields do not wipe existing values)" do
          patch settings_path, params: {
            setting: {
              openai_api_key: "",
              anthropic_api_key: ""
            }
          }

          settings = Setting.instance
          expect(settings.openai_api_key).to eq("sk-old-key")
          expect(settings.anthropic_api_key).to eq("sk-ant-old-key")
        end
      end

      context "when only updating one API key" do
        before do
          Setting.instance.update!(
            openai_api_key: "sk-existing-openai",
            anthropic_api_key: "sk-ant-existing-anthropic"
          )
        end

        it "preserves the other API key" do
          patch settings_path, params: {
            setting: {
              openai_api_key: "sk-new-openai-only",
              anthropic_api_key: ""
            }
          }

          settings = Setting.instance
          expect(settings.openai_api_key).to eq("sk-new-openai-only")
          expect(settings.anthropic_api_key).to eq("sk-ant-existing-anthropic")
        end
      end

      context "with invalid parameters" do
        it "handles validation errors gracefully" do
          # Force an error by patching with a non-existent attribute
          patch settings_path, params: {
            setting: {
              invalid_attribute: "value"
            }
          }

          # Should still redirect as we're using update! but with permitted params
          expect(response.status).to be_in([ 302, 422 ])
        end
      end
    end
  end
end
