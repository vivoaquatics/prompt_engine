module PromptEngine
  class SettingsController < ApplicationController
    before_action :load_settings

    def edit
      # Just display the form
    end

    def update
      if @settings.update(settings_params)
        redirect_to edit_settings_path, notice: "Settings have been updated successfully."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def load_settings
      @settings = Setting.instance
    end

    def settings_params
      # The "never overwrite a stored key with an empty-string value"
      # invariant lives on the Setting model (see
      # PromptEngine::Setting#retain_existing_api_keys_when_blank) so every
      # writer gets the same protection - not just this controller.
      params.require(:setting).permit(:openai_api_key, :anthropic_api_key)
    end
  end
end
