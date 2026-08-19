require "rails_helper"

module PromptEngine
  RSpec.describe "Versions", type: :request do
    let(:prompt) { create(:prompt, content: "Version 1 content") }
    let(:version_1) { prompt.versions.order(version_number: :asc).first }
    let(:version_2) do
      prompt.reload # ensure we have the latest state
      prompt.update!(content: "Version 2 content")
      prompt.versions.order(version_number: :desc).first
    end
    let(:version_3) do
      version_2 # ensure version 2 is created first
      prompt.reload # ensure we have the latest state
      prompt.update!(content: "Version 3 content")
      prompt.versions.order(version_number: :desc).first
    end

    before do
      # Ensure all versions are created
      version_1
      version_2
      version_3
    end

    describe "GET /prompt_engine/prompts/:prompt_id/versions" do
      it "returns a successful response" do
        get prompt_engine.prompt_versions_path(prompt)
        expect(response).to be_successful
      end

      it "displays versions in descending order" do
        get prompt_engine.prompt_versions_path(prompt)

        # Check that versions appear in the correct order in the response body
        version_positions = [ version_3, version_2, version_1 ].map do |version|
          response.body.index("Version #{version.version_number}")
        end

        expect(version_positions).to eq(version_positions.sort)
      end

      it "includes the prompt information" do
        get prompt_engine.prompt_versions_path(prompt)
        expect(response.body).to include(prompt.name)
      end

      context "when prompt doesn't exist" do
        it "returns not found" do
          get prompt_engine.prompt_versions_path(prompt_id: 99999)
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    describe "GET /prompt_engine/prompts/:prompt_id/versions/:id" do
      it "returns a successful response" do
        get prompt_engine.prompt_version_path(prompt, version_2)
        expect(response).to be_successful
      end

      it "displays the version details" do
        get prompt_engine.prompt_version_path(prompt, version_2)

        expect(response.body).to include("Version 2 content")
        expect(response.body).to include("Version #{version_2.version_number}")
      end

      it "includes the prompt information" do
        get prompt_engine.prompt_version_path(prompt, version_2)
        expect(response.body).to include(prompt.name)
      end

      context "when version doesn't exist" do
        it "returns not found" do
          get prompt_engine.prompt_version_path(prompt, id: 99999)
          expect(response).to have_http_status(:not_found)
        end
      end

      context "when version belongs to different prompt" do
        let(:other_prompt) { create(:prompt) }
        let(:other_version) { other_prompt.versions.first }

        it "returns not found" do
          get prompt_engine.prompt_version_path(prompt, other_version)
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    describe "GET /prompt_engine/prompts/:prompt_id/versions/:id/compare" do
      context "with both version IDs provided" do
        it "returns a successful response" do
          get prompt_engine.compare_prompt_version_path(prompt, version_2,
            version_a_id: version_1.id,
            version_b_id: version_3.id)
          expect(response).to be_successful
        end

        it "displays both versions for comparison" do
          get prompt_engine.compare_prompt_version_path(prompt, version_2,
            version_a_id: version_1.id,
            version_b_id: version_3.id)

          expect(response.body).to include("Version 1 content")
          expect(response.body).to include("Version 3 content")
        end

        it "shows changes between versions" do
          get prompt_engine.compare_prompt_version_path(prompt, version_2,
            version_a_id: version_1.id,
            version_b_id: version_2.id)

          # Check that the comparison view shows the differences
          expect(response.body).to include("Version 1 content")
          expect(response.body).to include("Version 2 content")
        end

        it "surfaces a Reasoning diff row when reasoning_effort differs between the compared versions" do
          reasoning_prompt = create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "low")
          version_a = reasoning_prompt.versions.first
          reasoning_prompt.update!(reasoning_effort: "xhigh")
          version_b = reasoning_prompt.versions.latest.first

          get prompt_engine.compare_prompt_version_path(reasoning_prompt, version_b,
            version_a_id: version_a.id,
            version_b_id: version_b.id)

          expect(response.body).to include("Reasoning")
        end

        it "does not surface a Reasoning diff row when reasoning_effort is unchanged" do
          reasoning_prompt = create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "low")
          version_a = reasoning_prompt.versions.first
          reasoning_prompt.update!(content: "Some other change")
          version_b = reasoning_prompt.versions.latest.first

          get prompt_engine.compare_prompt_version_path(reasoning_prompt, version_b,
            version_a_id: version_a.id,
            version_b_id: version_b.id)

          expect(response.body).not_to include("Reasoning")
        end
      end

      context "with only id parameter (compare with previous)" do
        it "compares with the previous version" do
          get prompt_engine.compare_prompt_version_path(prompt, version_2)

          expect(response).to be_successful
          expect(response.body).to include("Version 1 content")
          expect(response.body).to include("Version 2 content")
        end

        it "handles first version (no previous)" do
          get prompt_engine.compare_prompt_version_path(prompt, version_1)

          expect(response).to be_successful
          # When there's no previous version, it compares with itself
          expect(response.body).to include("Version 1 → Version 1")
        end
      end

      context "with missing version IDs" do
        it "falls back to comparing with previous version" do
          get prompt_engine.compare_prompt_version_path(prompt, version_2,
            version_a_id: "",
            version_b_id: "")

          # The controller falls back to comparing with previous version
          expect(response).to be_successful
        end
      end

      context "with invalid version IDs" do
        it "redirects with alert" do
          get prompt_engine.compare_prompt_version_path(prompt, version_2,
            version_a_id: 99999,
            version_b_id: 88888)

          expect(response).to redirect_to(prompt_engine.prompt_versions_path(prompt))
          follow_redirect!
          expect(response.body).to include("Please select two versions to compare")
        end
      end
    end

    describe "POST /prompt_engine/prompts/:prompt_id/versions/:id/restore" do
      let(:original_content) { prompt.content }

      before do
        prompt.update!(content: "Current content")
      end

      it "restores the prompt to the selected version" do
        post prompt_engine.restore_prompt_version_path(prompt, version_2)

        prompt.reload
        expect(prompt.content).to eq("Version 2 content")
      end

      it "updates all version attributes" do
        # Update prompt to create a version with specific attributes
        prompt.update!(
          content: "New content",
          system_message: "Old system message",
          model: "gpt-3.5-turbo",
          temperature: 0.5,
          max_tokens: 500
        )
        specific_version = prompt.versions.order(version_number: :desc).first

        # Update prompt again to change current state
        prompt.update!(content: "Different content", system_message: "Different message")

        post prompt_engine.restore_prompt_version_path(prompt, specific_version)

        prompt.reload
        expect(prompt.content).to eq("New content")
        expect(prompt.system_message).to eq("Old system message")
        expect(prompt.model).to eq("gpt-3.5-turbo")
        expect(prompt.temperature).to eq(0.5)
        expect(prompt.max_tokens).to eq(500)
      end

      it "redirects to the prompt with success notice" do
        post prompt_engine.restore_prompt_version_path(prompt, version_2)

        expect(response).to redirect_to(prompt_engine.prompt_path(prompt))
        follow_redirect!
        expect(response.body).to include("Prompt restored to version #{version_2.version_number}")
      end

      context "when restoration fails" do
        before do
          allow_any_instance_of(Prompt).to receive(:update!).and_raise(StandardError, "Update failed")
        end

        it "redirects with error message" do
          post prompt_engine.restore_prompt_version_path(prompt, version_2)

          expect(response).to redirect_to(prompt_engine.prompt_versions_path(prompt))
          follow_redirect!
          expect(response.body).to include("Failed to restore version: Update failed")
        end

        it "doesn't change the prompt" do
          expect {
            post prompt_engine.restore_prompt_version_path(prompt, version_2)
          }.not_to change { prompt.reload.content }
        end
      end

      context "when version doesn't exist" do
        it "returns not found" do
          post prompt_engine.restore_prompt_version_path(prompt, id: 99999)
          expect(response).to have_http_status(:not_found)
        end
      end

      context "with reasoning_effort" do
        let(:reasoning_prompt) { create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "high") }
        let!(:reasoning_version) { reasoning_prompt.versions.first }

        it "restores reasoning_effort along with the other attributes" do
          reasoning_prompt.update!(reasoning_effort: nil)

          post prompt_engine.restore_prompt_version_path(reasoning_prompt, reasoning_version)

          expect(reasoning_prompt.reload.reasoning_effort).to eq("high")
        end

        it "labels the new version 'Restored from version N', not 'Updated: ...'" do
          reasoning_prompt.update!(reasoning_effort: nil)

          post prompt_engine.restore_prompt_version_path(reasoning_prompt, reasoning_version)

          latest = reasoning_prompt.reload.versions.latest.first
          expect(latest.change_description).to eq("Restored from version #{reasoning_version.version_number}")
        end

        it "sanitizes a reasoning_effort no longer valid for the version's own stored model instead of rejecting the restore" do
          reasoning_version.update_column(:reasoning_effort, "not-a-real-value")
          reasoning_prompt.update!(content: "Different content")

          post prompt_engine.restore_prompt_version_path(reasoning_prompt, reasoning_version)

          expect(response).to redirect_to(prompt_engine.prompt_path(reasoning_prompt))
          expect(reasoning_prompt.reload.reasoning_effort).to be_nil
        end
      end
    end
  end
end
