require "rails_helper"

module PromptEngine
  RSpec.describe Setting, type: :model do
    describe "table name" do
      it "uses the correct table" do
        expect(described_class.table_name).to eq("prompt_engine_settings")
      end
    end

    describe ".instance" do
      context "when no settings exist" do
        before { described_class.destroy_all }

        it "creates a new settings record" do
          expect { described_class.instance }.to change(described_class, :count).by(1)
        end

        it "returns the settings instance" do
          settings = described_class.instance
          expect(settings).to be_a(described_class)
          expect(settings).to be_persisted
        end
      end

      context "when settings already exist" do
        let!(:existing_settings) { described_class.create! }

        it "returns the existing settings" do
          expect(described_class.instance).to eq(existing_settings)
        end

        it "does not create a new record" do
          expect { described_class.instance }.not_to change(described_class, :count)
        end
      end
    end

    describe "blank-value retention (never overwrite a stored key with blank)" do
      let(:settings) { described_class.instance }

      before do
        settings.update!(openai_api_key: "sk-existing-key", anthropic_api_key: "sk-ant-existing-key")
      end

      it "restores the existing key when updated directly with a blank value" do
        settings.update!(openai_api_key: "")

        expect(settings.reload.openai_configured?).to be(true)
        expect(settings.openai_api_key).to eq("sk-existing-key")
      end

      it "leaves the other provider's key untouched" do
        settings.update!(openai_api_key: "")

        expect(settings.anthropic_api_key).to eq("sk-ant-existing-key")
      end

      it "restores the existing key when updated with a whitespace-only value" do
        settings.update!(openai_api_key: "   ")

        expect(settings.reload.openai_configured?).to be(true)
        expect(settings.openai_api_key).to eq("sk-existing-key")
      end

      it "restores the existing key when updated with a Unicode-whitespace-only value" do
        settings.update!(openai_api_key: " ")

        expect(settings.reload.openai_configured?).to be(true)
        expect(settings.openai_api_key).to eq("sk-existing-key")
      end
    end

    describe "blank submission for a provider that has never had a key stored" do
      let(:settings) { described_class.instance }

      it "normalizes the attribute to nil rather than persisting an empty string" do
        settings.update!(anthropic_api_key: "   ")

        settings.reload
        expect(settings.anthropic_configured?).to be(false)
        expect(settings.anthropic_api_key).to be_nil
      end
    end

    describe "encrypted attributes" do
      let(:settings) { described_class.instance }

      it "encrypts the openai_api_key" do
        settings.openai_api_key = "sk-test-key"
        settings.save!

        # The encrypted value should be different from the plain text
        encrypted_value = described_class.connection.select_value(
          "SELECT openai_api_key FROM #{described_class.table_name} WHERE id = #{settings.id}"
        )
        expect(encrypted_value).not_to eq("sk-test-key")

        # But we can still read the decrypted value
        settings.reload
        expect(settings.openai_api_key).to eq("sk-test-key")
      end

      it "encrypts the anthropic_api_key" do
        settings.anthropic_api_key = "sk-ant-test-key"
        settings.save!

        # The encrypted value should be different from the plain text
        encrypted_value = described_class.connection.select_value(
          "SELECT anthropic_api_key FROM #{described_class.table_name} WHERE id = #{settings.id}"
        )
        expect(encrypted_value).not_to eq("sk-ant-test-key")

        # But we can still read the decrypted value
        settings.reload
        expect(settings.anthropic_api_key).to eq("sk-ant-test-key")
      end
    end
  end
end
