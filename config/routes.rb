Rails.application.routes.draw do
  devise_for :users

  resources :metadata_types do
    resources :metadata
  end

  root "home#index"
end
