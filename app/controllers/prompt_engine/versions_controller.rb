module PromptEngine
  class VersionsController < ApplicationController
    before_action :set_prompt
    before_action :set_version, only: [ :show, :restore ]
    before_action :set_compare_versions, only: [ :compare ]

    def index
      @versions = @prompt.versions
    end

    def show
    end

    def compare
      if @version_a && @version_b
        @changes = calculate_changes(@version_a, @version_b)
      else
        redirect_to prompt_versions_path(@prompt), alert: "Please select two versions to compare"
      end
    end

    def restore
      # Delegate to the model's own restore! (rather than duplicating its
      # update!/attribute-hash logic here): it already sanitizes an
      # invalid-for-its-model reasoning_effort so the restore can never be
      # vetoed by the inclusion validator, and it correctly stamps the
      # resulting version's change_description as "Restored from version N".
      @version.restore!
      redirect_to @prompt, notice: "Prompt restored to version #{@version.version_number}"
    rescue => e
      redirect_to prompt_versions_path(@prompt), alert: "Failed to restore version: #{e.message}"
    end

    private

    def set_prompt
      @prompt = Prompt.find(params[:prompt_id])
    end

    def set_version
      @version = @prompt.versions.find(params[:id])
    end

    def set_compare_versions
      if params[:version_a_id].present? && params[:version_b_id].present?
        @version_a = @prompt.versions.find_by(id: params[:version_a_id])
        @version_b = @prompt.versions.find_by(id: params[:version_b_id])
      elsif params[:id].present?
        @version_b = @prompt.versions.find(params[:id])
        @version_a = @prompt.versions.where("version_number < ?", @version_b.version_number).order(version_number: :desc).first
        @version_a ||= @version_b
      end
    end

    def calculate_changes(version_a, version_b)
      {
        content: {
          old: version_a.content,
          new: version_b.content,
          changed: version_a.content != version_b.content
        },
        system_message: {
          old: version_a.system_message,
          new: version_b.system_message,
          changed: version_a.system_message != version_b.system_message
        },
        model: {
          old: version_a.model,
          new: version_b.model,
          changed: version_a.model != version_b.model
        },
        temperature: {
          old: version_a.temperature,
          new: version_b.temperature,
          changed: version_a.temperature != version_b.temperature
        },
        max_tokens: {
          old: version_a.max_tokens,
          new: version_b.max_tokens,
          changed: version_a.max_tokens != version_b.max_tokens
        },
        reasoning_effort: {
          old: version_a.reasoning_effort,
          new: version_b.reasoning_effort,
          changed: version_a.reasoning_effort != version_b.reasoning_effort
        }
      }
    end
  end
end
