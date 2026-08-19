require 'rails_helper'

module PromptEngine
  RSpec.describe PromptVersion, type: :model do
    describe 'associations' do
      it 'belongs to a prompt' do
        version = PromptVersion.new
        association = version.class.reflect_on_association(:prompt)
        expect(association.macro).to eq(:belongs_to)
        expect(association.options[:class_name]).to eq('PromptEngine::Prompt')
      end
    end

    describe 'validations' do
      it 'validates presence of version_number' do
        version = PromptVersion.new(version_number: nil)
        expect(version).not_to be_valid
        expect(version.errors[:version_number]).to include("can't be blank")
      end

      it 'validates presence of content' do
        version = PromptVersion.new(content: nil)
        expect(version).not_to be_valid
        expect(version.errors[:content]).to include("can't be blank")
      end

      it 'validates version_number is greater than 0' do
        version = PromptVersion.new(version_number: 0)
        expect(version).not_to be_valid
        expect(version.errors[:version_number]).to include('must be greater than 0')
      end

      context 'uniqueness of version_number' do
        let(:prompt) { create(:prompt) }

        it 'validates uniqueness of version_number scoped to prompt' do
          # The prompt already has version 1 from auto-creation
          version2 = build(:prompt_version, prompt: prompt, version_number: 1)
          expect(version2).not_to be_valid
          expect(version2.errors[:version_number]).to include('has already been taken')
        end

        it 'allows same version_number for different prompts' do
          other_prompt = create(:prompt)
          # Both prompts have version 1, which is fine
          expect(prompt.versions.first.version_number).to eq(1)
          expect(other_prompt.versions.first.version_number).to eq(1)
        end
      end
    end

    describe 'version number auto-increment' do
      let(:prompt) { create(:prompt) }

      context 'when no additional versions exist' do
        it 'auto-increments from existing version' do
          # Prompt already has version 1 from creation
          expect(prompt.versions.count).to eq(1)
          expect(prompt.versions.first.version_number).to eq(1)

          version = PromptVersion.create!(
            prompt: prompt,
            content: 'Test content',
            system_message: 'Test system message',
            model: 'gpt-4',
            temperature: 0.7,
            max_tokens: 1000
          )
          expect(version.version_number).to eq(2)
        end
      end

      context 'when multiple versions exist' do
        before do
          # Prompt already has version 1, so we create version 2
          create(:prompt_version, prompt: prompt, version_number: 2)
        end

        it 'auto-increments to next version number' do
          version = PromptVersion.create!(
            prompt: prompt,
            content: 'New content',
            system_message: 'New system message',
            model: 'gpt-4',
            temperature: 0.8,
            max_tokens: 1500
          )
          expect(version.version_number).to eq(3)
        end
      end
    end

    describe 'content immutability' do
      let(:prompt) { create(:prompt) }
      let(:version) { prompt.versions.first }

      it 'prevents updating content after creation' do
        original_content = version.content
        version.content = 'Changed content'
        expect(version.save).to be false
        expect(version.errors[:content]).to include('cannot be changed after creation')
        expect(version.reload.content).to eq(original_content)
      end

      it 'prevents updating system_message after creation' do
        original_message = version.system_message
        version.system_message = 'Changed message'
        expect(version.save).to be false
        expect(version.errors[:system_message]).to include('cannot be changed after creation')
        expect(version.reload.system_message).to eq(original_message)
      end

      it 'prevents updating model after creation' do
        original_model = version.model
        version.model = 'gpt-3.5-turbo'
        expect(version.save).to be false
        expect(version.errors[:model]).to include('cannot be changed after creation')
        expect(version.reload.model).to eq(original_model)
      end

      it 'prevents updating temperature after creation' do
        original_temp = version.temperature
        version.temperature = 0.9
        expect(version.save).to be false
        expect(version.errors[:temperature]).to include('cannot be changed after creation')
        expect(version.reload.temperature).to eq(original_temp)
      end

      it 'prevents updating max_tokens after creation' do
        original_tokens = version.max_tokens
        version.max_tokens = 2000
        expect(version.save).to be false
        expect(version.errors[:max_tokens]).to include('cannot be changed after creation')
        expect(version.reload.max_tokens).to eq(original_tokens)
      end

      it 'prevents updating reasoning_effort after creation' do
        original_reasoning_effort = version.reasoning_effort
        version.reasoning_effort = 'high'
        expect(version.save).to be false
        expect(version.errors[:reasoning_effort]).to include('cannot be changed after creation')
        expect(version.reload.reasoning_effort).to eq(original_reasoning_effort)
      end

      it 'allows updating change_description' do
        version.change_description = 'Updated description'
        expect(version.save).to be true
        expect(version.reload.change_description).to eq('Updated description')
      end
    end

    describe 'scopes' do
      let(:prompt) { create(:prompt) }
      let!(:version1) { prompt.versions.first.tap { |v| v.update_column(:created_at, 3.days.ago) } }
      let!(:version2) { create(:prompt_version, prompt: prompt, version_number: 2, created_at: 2.days.ago) }
      let!(:version3) { create(:prompt_version, prompt: prompt, version_number: 3, created_at: 1.day.ago) }

      describe '.latest' do
        it 'returns versions ordered by version_number descending' do
          expect(prompt.versions.latest).to eq([ version3, version2, version1 ])
        end
      end

      describe '.chronological' do
        it 'returns versions ordered by created_at ascending' do
          expect(PromptVersion.where(prompt: prompt).chronological.to_a).to eq([ version1, version2, version3 ])
        end
      end
    end

    describe '#restore!' do
      let(:prompt) do
        create(:prompt,
          content: 'Old content',
          system_message: 'Old message',
          model: 'gpt-3.5-turbo',
          temperature: 0.5,
          max_tokens: 500,
          metadata: { 'key' => 'value' }
        )
      end
      let!(:old_version) do
        # Store the initial version
        prompt.versions.first
      end

      it 'restores the prompt to the version state' do
        # Verify old_version has the expected content
        expect(old_version.content).to eq('Old content')

        # Now update the prompt to something different
        prompt.update!(content: 'Different content', system_message: 'Different message')
        expect(prompt.content).to eq('Different content')

        # Restore to the old version
        old_version.restore!
        prompt.reload

        expect(prompt.content).to eq('Old content')
        expect(prompt.system_message).to eq('Old message')
        expect(prompt.model).to eq('gpt-3.5-turbo')
        expect(prompt.temperature).to eq(0.5)
        expect(prompt.max_tokens).to eq(500)
        expect(prompt.metadata).to eq({ 'key' => 'value' })
      end

      it 'creates a new version when restoring' do
        # Verify initial state
        expect(prompt.versions.count).to eq(1)
        expect(prompt.content).to eq('Old content')

        # Debug: Check if attributes are changing
        expect(prompt.system_message).to eq('Old message')

        # Update the prompt to something different - force reload to ensure clean state
        prompt.reload
        expect(prompt.versioned_attributes_changed?).to be false

        prompt.content = 'Different content'
        prompt.system_message = 'Different message'
        expect(prompt.versioned_attributes_changed?).to be true

        prompt.save!

        # Check version was created
        expect(prompt.reload.versions.count).to eq(2)

        # Now restore to old version
        old_version.restore!

        # Should have created exactly one new version
        expect(prompt.versions.count).to eq(3)

        new_version = prompt.versions.latest.first
        expect(new_version.content).to eq('Old content')
        expect(new_version.change_description).to include('Restored from version')
      end

      context 'when the version has a reasoning_effort valid for its own model' do
        let(:prompt) do
          create(:prompt,
            content: 'Old content',
            model: 'gpt-5.6-sol',
            reasoning_effort: 'xhigh'
          )
        end

        it 'restores reasoning_effort along with the other attributes' do
          prompt.update!(content: 'Different content', reasoning_effort: nil)
          expect(prompt.reasoning_effort).to be_nil

          old_version.restore!
          prompt.reload

          expect(prompt.content).to eq('Old content')
          expect(prompt.model).to eq('gpt-5.6-sol')
          expect(prompt.reasoning_effort).to eq('xhigh')
        end
      end

      context 'when the version has a reasoning_effort no longer valid for its stored model' do
        let(:prompt) do
          create(:prompt,
            content: 'Old content',
            model: 'gpt-5.6-sol',
            reasoning_effort: 'xhigh'
          )
        end

        it 'sanitizes the invalid value to nil instead of raising' do
          # Simulate a legacy/corrupt version row whose reasoning_effort is no
          # longer valid for the model it was captured against - bypass
          # normal validation the same way a config change removing a value
          # from model_reasoning_options would leave a stale row behind.
          old_version.update_column(:reasoning_effort, 'not-a-real-value')

          prompt.update!(content: 'Different content')

          expect { old_version.restore! }.not_to raise_error

          prompt.reload
          expect(prompt.content).to eq('Old content')
          expect(prompt.model).to eq('gpt-5.6-sol')
          expect(prompt.reasoning_effort).to be_nil
        end
      end

      context 'when the live prompt has since moved to a different model entirely' do
        let(:prompt) do
          create(:prompt, content: 'Old content', model: 'gpt-5.6-sol', reasoning_effort: 'xhigh')
        end

        it 'restores both the version\'s own model and reasoning_effort, ignoring the live prompt\'s current model' do
          # The live prompt has since moved to a non-reasoning model - restore
          # should bring back the version's own (self-consistent) model +
          # reasoning_effort pairing, not be influenced by what the prompt
          # currently holds.
          prompt.update!(model: 'gpt-4o', reasoning_effort: nil)

          old_version.restore!
          prompt.reload

          expect(prompt.model).to eq('gpt-5.6-sol')
          expect(prompt.reasoning_effort).to eq('xhigh')
        end
      end
    end

    describe '#to_prompt_attributes' do
      let(:prompt) { create(:prompt) }
      let(:version) do
        # Create a version directly with specific attributes
        prompt.versions.create!(
          content: 'Version content',
          system_message: 'Version message',
          model: 'gpt-4',
          temperature: 0.7,
          max_tokens: 1000,
          reasoning_effort: nil,
          metadata: { 'foo' => 'bar' }
        )
      end

      it 'returns a hash of prompt attributes' do
        attributes = version.to_prompt_attributes

        expect(attributes).to eq({
          content: 'Version content',
          system_message: 'Version message',
          model: 'gpt-4',
          temperature: 0.7,
          max_tokens: 1000,
          reasoning_effort: nil,
          metadata: { 'foo' => 'bar' }
        })
      end

      context 'when the version has a reasoning_effort' do
        let(:version) do
          prompt.versions.create!(
            content: 'Version content',
            system_message: 'Version message',
            model: 'gpt-5.6-sol',
            temperature: 0.7,
            max_tokens: 1000,
            reasoning_effort: 'high',
            metadata: {}
          )
        end

        it 'includes it in the returned hash' do
          expect(version.to_prompt_attributes[:reasoning_effort]).to eq('high')
        end
      end
    end
  end
end
