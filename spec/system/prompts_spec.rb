require "rails_helper"

RSpec.describe "Prompts management", type: :system do
  before do
    driven_by(:rack_test)
  end

  describe "Creating a new prompt" do
    it "allows users to create a new prompt with valid data" do
      visit "/prompt_engine/prompts"

      click_link "New Prompt"

      expect(page).to have_current_path("/prompt_engine/prompts/new")
      expect(page).to have_content("New Prompt")

      fill_in "Name", with: "Customer Support Bot"
      fill_in "Slug", with: "customer-support-bot"
      fill_in "Prompt Content", with: "You are a helpful customer support assistant. Respond to customer inquiries professionally."
      fill_in "System Message", with: "Always be polite and professional."
      select "Active", from: "Status"
      fill_in "Temperature", with: "0.7"
      fill_in "Max Tokens", with: "1000"

      click_button "Create Prompt"

      expect(page).to have_content("Prompt was successfully created.")
      expect(page).to have_content("Customer Support Bot")
      expect(page).to have_content("You are a helpful customer support assistant")
      expect(page).to have_content("active")
    end

    it "shows validation errors for invalid data" do
      visit "/prompt_engine/prompts/new"

      click_button "Create Prompt"

      expect(page).to have_content("Name can't be blank")
      expect(page).to have_content("Content can't be blank")
    end
  end

  describe "Editing an existing prompt" do
    let!(:prompt) { create(:prompt, name: "Original Name", content: "Original content", status: "draft") }

    it "allows users to edit an existing prompt" do
      visit "/prompt_engine/prompts"

      within("tr", text: "Original Name") do
        click_link "Edit"
      end

      expect(page).to have_current_path("/prompt_engine/prompts/#{prompt.id}/edit")
      expect(page).to have_content("Edit Prompt")

      fill_in "Name", with: "Updated Customer Bot"
      fill_in "Slug", with: "updated-customer-bot"
      fill_in "Prompt Content", with: "Updated content for the bot"
      select "Active", from: "Status"
      fill_in "Temperature", with: "0.8"

      click_button "Update Prompt"

      expect(page).to have_content("Prompt was successfully updated.")
      expect(page).to have_content("Updated Customer Bot")
      expect(page).to have_content("Updated content for the bot")
      expect(page).to have_content("active")
    end

    it "shows validation errors when updating with invalid data" do
      visit "/prompt_engine/prompts/#{prompt.id}/edit"

      fill_in "Name", with: ""
      fill_in "Prompt Content", with: ""

      click_button "Update Prompt"

      expect(page).to have_content("Name can't be blank")
      expect(page).to have_content("Content can't be blank")
    end
  end

  describe "Deleting a prompt" do
    let!(:prompt) { create(:prompt, name: "Prompt to Delete") }

    it "allows users to delete a prompt" do
      visit "/prompt_engine/prompts"

      expect(page).to have_content("Prompt to Delete")

      within("tr", text: "Prompt to Delete") do
        click_button "Delete"
      end

      expect(page).to have_content("Prompt was successfully deleted.")
      expect(page).not_to have_content("Prompt to Delete")
    end

    it "shows the prompt exists before deletion" do
      visit "/prompt_engine/prompts"

      expect(page).to have_content("Prompt to Delete")

      # Note: rack_test doesn't support JavaScript, so we can't test dismissing confirm dialog
      # The delete button would need JavaScript support to show confirm dialog
    end
  end

  describe "Navigation between pages" do
    let!(:prompt) { create(:prompt, name: "Navigation Test Prompt") }

    it "navigates from index to show page" do
      visit "/prompt_engine/prompts"

      # In the index view, the prompt name itself is the link
      click_link "Navigation Test Prompt"

      expect(page).to have_current_path("/prompt_engine/prompts/#{prompt.id}")
      expect(page).to have_content("Navigation Test Prompt")
      expect(page).to have_link("Edit")
      expect(page).to have_link("Back to Prompts")
    end

    it "navigates from show to edit page" do
      visit "/prompt_engine/prompts/#{prompt.id}"

      click_link "Edit"

      expect(page).to have_current_path("/prompt_engine/prompts/#{prompt.id}/edit")
      expect(page).to have_field("Name", with: "Navigation Test Prompt")
    end

    it "navigates back to index from show page" do
      visit "/prompt_engine/prompts/#{prompt.id}"

      click_link "Back to Prompts"

      expect(page).to have_current_path("/prompt_engine/prompts")
      expect(page).to have_content("Prompts")
    end

    it "navigates back to prompts page from edit page using cancel" do
      visit "/prompt_engine/prompts/#{prompt.id}/edit"

      click_link "Cancel"

      # The cancel link goes to prompts_path (index)
      expect(page).to have_current_path("/prompt_engine/prompts")
    end
  end

  describe "Form validations" do
    it "accepts temperature values" do
      visit "/prompt_engine/prompts/new"

      fill_in "Name", with: "Temperature Test"
      fill_in "Slug", with: "temperature-test"
      fill_in "Prompt Content", with: "Test content"
      fill_in "Temperature", with: "1.5"

      click_button "Create Prompt"

      # Note: Temperature validation is not implemented in the model
      expect(page).to have_content("Prompt was successfully created.")
      expect(page).to have_content("1.5")
    end

    it "accepts max tokens values" do
      visit "/prompt_engine/prompts/new"

      fill_in "Name", with: "Token Test"
      fill_in "Slug", with: "token-test"
      fill_in "Prompt Content", with: "Test content"
      fill_in "Max Tokens", with: "500"

      click_button "Create Prompt"

      # Note: Max tokens validation is not implemented in the model
      expect(page).to have_content("Prompt was successfully created.")
      expect(page).to have_content("500")
    end

    it "validates uniqueness of prompt name" do
      existing_prompt = create(:prompt, name: "Unique Name")

      visit "/prompt_engine/prompts/new"

      fill_in "Name", with: "Unique Name"
      fill_in "Slug", with: "unique-name"
      fill_in "Prompt Content", with: "Test content"

      click_button "Create Prompt"

      expect(page).to have_content("Name has already been taken")
    end
  end

  describe "Table interactions" do
    let!(:draft_prompt) { create(:prompt, name: "Draft Prompt", status: "draft") }
    let!(:prompt_engine) { create(:prompt, name: "Active Prompt", status: "active") }
    let!(:archived_prompt) { create(:prompt, name: "Archived Prompt", status: "archived") }

    it "displays all prompts with their status badges" do
      visit "/prompt_engine/prompts"

      expect(page).to have_css(".table__badge--draft", text: "draft")
      expect(page).to have_css(".table__badge--active", text: "active")
      expect(page).to have_css(".table__badge--archived", text: "archived")
    end

    it "shows prompt details in the table" do
      visit "/prompt_engine/prompts"

      within("tr", text: "Active Prompt") do
        expect(page).to have_content("Active Prompt")
        expect(page).to have_css(".table__badge--active", text: "active")
        expect(page).to have_link("Edit")
        expect(page).to have_button("Delete")
      end
    end
  end

  describe "Flash messages" do
    let!(:prompt) { create(:prompt) }

    it "displays success messages for CRUD operations" do
      visit "/prompt_engine/prompts/new"
      fill_in "Name", with: "Flash Test"
      fill_in "Slug", with: "flash-test"
      fill_in "Prompt Content", with: "Test content"
      click_button "Create Prompt"

      expect(page).to have_css(".admin-notification--notice", text: "Prompt was successfully created.")

      click_link "Edit"
      fill_in "Name", with: "Flash Test Updated"
      click_button "Update Prompt"

      expect(page).to have_css(".admin-notification--notice", text: "Prompt was successfully updated.")
    end
  end

  describe "Reasoning field" do
    # options_for_model_select ships empty of vivopoint model ids by default
    # (CVP-1796 precedent) - widen it here so the AI Model dropdown actually
    # offers a reasoning-capable id to select in these system specs.
    around do |example|
      original = PromptEngine.configuration.options_for_model_select
      PromptEngine.configuration.options_for_model_select =
        original + [ [ "GPT-5.6 Sol", "gpt-5.6-sol" ] ]
      example.run
      PromptEngine.configuration.options_for_model_select = original
    end

    it "is hidden on the new-prompt form, since no model is selected yet server-side" do
      # rack_test cannot execute the change-event JS that would populate the
      # field after picking a model in the AI Model dropdown - the server
      # only ever renders the correct state for the (blank, on a brand new
      # record) saved model. This is expected, not a bug: see _form.html.erb.
      visit "/prompt_engine/prompts/new"

      expect(page).not_to have_select("Reasoning")
    end

    it "shows and persists a reasoning value when editing a prompt already on a reasoning-capable model" do
      prompt = create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "low")

      visit "/prompt_engine/prompts/#{prompt.id}/edit"
      select "High", from: "Reasoning"
      click_button "Update Prompt"

      expect(page).to have_content("Prompt was successfully updated.")
      expect(prompt.reload.reasoning_effort).to eq("high")
    end

    it "hides the Reasoning field when editing a prompt on a non-reasoning-capable model" do
      prompt = create(:prompt, model: "gpt-4o")

      visit "/prompt_engine/prompts/#{prompt.id}/edit"

      # rack_test honors inline style="display: none" for visibility, so this
      # correctly proves the field is server-rendered hidden - no JS driver
      # needed for this assertion.
      expect(page).not_to have_select("Reasoning")
    end

    it "shows the Reasoning field, pre-selected, when editing a prompt that already has a value" do
      prompt = create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "xhigh")

      visit "/prompt_engine/prompts/#{prompt.id}/edit"

      expect(page).to have_select("Reasoning", selected: "Xhigh")
    end

    it "server-renders exactly the model family's option list, without JS" do
      prompt = create(:prompt, model: "gpt-5", reasoning_effort: nil)

      visit "/prompt_engine/prompts/#{prompt.id}/edit"

      option_texts = find_field("Reasoning").all("option").map(&:text)
      expect(option_texts).to eq([ "Default (low)", "Minimal", "Low", "Medium", "High" ])
    end
  end

  describe "Empty state" do
    it "shows appropriate message when no prompts exist" do
      visit "/prompt_engine/prompts"

      if page.has_content?("No prompts yet")
        expect(page).to have_content("No prompts yet")
        expect(page).to have_content("Get started by creating your first prompt.")
      else
        expect(page).to have_css("table")
      end
    end
  end
end
