# This file has been migrated to a request spec at:
# spec/requests/prompt_engine/prompts_spec.rb
#
# Controller specs are deprecated in favor of request specs which test
# the full request/response cycle including routing and middleware.
# See docs/CONTROLLER-TESTS.md for migration guidelines.

# require 'rails_helper'
#
# module PromptEngine
#   RSpec.describe PromptsController, type: :controller do
#     routes { PromptEngine::Engine.routes }
#
#     let(:valid_attributes) do
#       {
#         name: 'Test Prompt',
#         description: 'A test prompt',
#         content: 'Generate a {{type}} response',
#         system_message: 'You are a helpful assistant',
#         model: 'gpt-4',
#         temperature: 0.7,
#         max_tokens: 1000,
#         status: 'draft'
#       }
#     end
#
#     let(:invalid_attributes) do
#       {
#         name: '',
#         content: '',
#         description: 'Invalid prompt without required fields'
#       }
#     end
#
#     describe 'GET #index' do
#       it 'returns a success response' do
#         get :index
#         expect(response).to be_successful
#       end
#     end
#
#     describe 'GET #show' do
#       let(:prompt) { create(:prompt) }
#
#       it 'returns a success response' do
#         get :show, params: { id: prompt.to_param }
#         expect(response).to be_successful
#       end
#     end
#
#     describe 'GET #new' do
#       it 'returns a success response' do
#         get :new
#         expect(response).to be_successful
#       end
#     end
#
#     describe 'POST #create' do
#       context 'with valid params' do
#         it 'creates a new Prompt' do
#           expect {
#             post :create, params: { prompt: valid_attributes }
#           }.to change(PromptEngine::Prompt, :count).by(1)
#         end
#
#         it 'redirects to the created prompt' do
#           post :create, params: { prompt: valid_attributes }
#           expect(response).to redirect_to(prompt_path(PromptEngine::Prompt.last))
#         end
#
#         it 'sets a success notice' do
#           post :create, params: { prompt: valid_attributes }
#           expect(flash[:notice]).to eq('Prompt was successfully created.')
#         end
#       end
#
#       context 'with invalid params' do
#         it 'does not create a new Prompt' do
#           expect {
#             post :create, params: { prompt: invalid_attributes }
#           }.not_to change(PromptEngine::Prompt, :count)
#         end
#
#         it 'returns unprocessable entity status' do
#           post :create, params: { prompt: invalid_attributes }
#           expect(response).to have_http_status(:unprocessable_content)
#         end
#       end
#     end
#
#     describe 'GET #edit' do
#       let(:prompt) { create(:prompt) }
#
#       it 'returns a success response' do
#         get :edit, params: { id: prompt.to_param }
#         expect(response).to be_successful
#       end
#     end
#
#     describe 'PUT #update' do
#       let(:prompt) { create(:prompt) }
#
#       context 'with valid params' do
#         let(:new_attributes) do
#           {
#             name: 'Updated Prompt Name',
#             description: 'Updated description',
#             temperature: 0.9
#           }
#         end
#
#         it 'updates the requested prompt' do
#           put :update, params: { id: prompt.to_param, prompt: new_attributes }
#           prompt.reload
#           expect(prompt.name).to eq('Updated Prompt Name')
#           expect(prompt.description).to eq('Updated description')
#           expect(prompt.temperature).to eq(0.9)
#         end
#
#         it 'redirects to the prompt' do
#           put :update, params: { id: prompt.to_param, prompt: new_attributes }
#           expect(response).to redirect_to(prompt_path(prompt))
#         end
#
#         it 'sets a success notice' do
#           put :update, params: { id: prompt.to_param, prompt: new_attributes }
#           expect(flash[:notice]).to eq('Prompt was successfully updated.')
#         end
#       end
#
#       context 'with invalid params' do
#         it 'does not update the prompt' do
#           original_name = prompt.name
#           put :update, params: { id: prompt.to_param, prompt: invalid_attributes }
#           prompt.reload
#           expect(prompt.name).to eq(original_name)
#         end
#
#         it 'returns unprocessable entity status' do
#           put :update, params: { id: prompt.to_param, prompt: invalid_attributes }
#           expect(response).to have_http_status(:unprocessable_content)
#         end
#       end
#     end
#
#     describe 'DELETE #destroy' do
#       let!(:prompt) { create(:prompt) }
#
#       it 'destroys the requested prompt' do
#         expect {
#           delete :destroy, params: { id: prompt.to_param }
#         }.to change(PromptEngine::Prompt, :count).by(-1)
#       end
#
#       it 'redirects to the prompts list' do
#         delete :destroy, params: { id: prompt.to_param }
#         expect(response).to redirect_to(prompts_path)
#       end
#
#       it 'sets a success notice' do
#         delete :destroy, params: { id: prompt.to_param }
#         expect(flash[:notice]).to eq('Prompt was successfully deleted.')
#       end
#     end
#   end
# end
