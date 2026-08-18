require "rails_helper"

module PromptEngine
  RSpec.describe "EvalSets grader types", type: :request do
    let(:prompt) { create(:prompt) }

    xdescribe "POST /prompt_engine/prompts/:prompt_id/eval_sets" do
      context "with exact_match grader type" do
        it "creates eval set without grader_config" do
          post prompt_engine.prompt_eval_sets_path(prompt), params: {
            eval_set: {
              name: "Exact Match Tests",
              description: "Test exact match grading",
              grader_type: "exact_match"
            }
          }

          expect(response).to redirect_to(prompt_engine.prompt_eval_set_path(prompt, EvalSet.last))
          eval_set = EvalSet.last
          expect(eval_set.grader_type).to eq("exact_match")
          expect(eval_set.grader_config).to eq({})
        end
      end

      context "with regex grader type" do
        it "creates eval set with regex pattern" do
          post prompt_engine.prompt_eval_sets_path(prompt), params: {
            eval_set: {
              name: "Regex Tests",
              description: "Test regex grading",
              grader_type: "regex",
              grader_config: {
                pattern: "^Hello.*world$"
              }
            }
          }

          expect(response).to redirect_to(prompt_engine.prompt_eval_set_path(prompt, EvalSet.last))
          eval_set = EvalSet.last
          expect(eval_set.grader_type).to eq("regex")
          expect(eval_set.grader_config["pattern"]).to eq("^Hello.*world$")
        end

        it "fails with invalid regex pattern" do
          post prompt_engine.prompt_eval_sets_path(prompt), params: {
            eval_set: {
              name: "Invalid Regex Tests",
              grader_type: "regex",
              grader_config: {
                pattern: "[invalid"
              }
            }
          }

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("invalid regex pattern")
        end
      end

      context "with json_schema grader type" do
        it "creates eval set with JSON schema" do
          schema = {
            type: "object",
            properties: {
              name: {type: "string"},
              age: {type: "integer"}
            },
            required: ["name"]
          }

          post prompt_engine.prompt_eval_sets_path(prompt), params: {
            eval_set: {
              name: "JSON Schema Tests",
              grader_type: "json_schema",
              grader_config: {
                schema: schema
              }
            }
          }

          expect(response).to redirect_to(prompt_engine.prompt_eval_set_path(prompt, EvalSet.last))
          eval_set = EvalSet.last
          expect(eval_set.grader_type).to eq("json_schema")
          expect(eval_set.grader_config["schema"]).to eq(schema.stringify_keys)
        end
      end
    end

    xdescribe "PATCH /prompt_engine/prompts/:prompt_id/eval_sets/:id" do
      let(:eval_set) { create(:eval_set, prompt: prompt, grader_type: "exact_match") }

      it "updates grader type to regex with config" do
        patch prompt_engine.prompt_eval_set_path(prompt, eval_set), params: {
          eval_set: {
            grader_type: "regex",
            grader_config: {
              pattern: "\\d{3}-\\d{3}-\\d{4}"
            }
          }
        }

        expect(response).to redirect_to(prompt_engine.prompt_eval_set_path(prompt, eval_set))
        eval_set.reload
        expect(eval_set.grader_type).to eq("regex")
        expect(eval_set.grader_config["pattern"]).to eq("\\d{3}-\\d{3}-\\d{4}")
      end

      it "clears grader_config when changing to exact_match" do
        eval_set.update!(grader_type: "regex", grader_config: {pattern: "test"})

        patch prompt_engine.prompt_eval_set_path(prompt, eval_set), params: {
          eval_set: {
            grader_type: "exact_match",
            grader_config: {}
          }
        }

        expect(response).to redirect_to(prompt_engine.prompt_eval_set_path(prompt, eval_set))
        eval_set.reload
        expect(eval_set.grader_type).to eq("exact_match")
        expect(eval_set.grader_config).to eq({})
      end
    end
  end
end
