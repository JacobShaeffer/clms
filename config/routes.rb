Rails.application.routes.draw do
  devise_for :users

  resources :metadata_types do
    member do
      get :metadata_values
    end

    resources :metadata
  end

  root "home#index"
end
