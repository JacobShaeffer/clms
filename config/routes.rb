Rails.application.routes.draw do
  resources :metadata_types
  devise_for :users

  resources :metadata_types do
    resources :metadata
  end

  root "home#index"
end
