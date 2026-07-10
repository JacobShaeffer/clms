Rails.application.routes.draw do
  devise_for :users

  resources :contents, only: %i[ index new create ] do
    collection do
      get :table
    end
  end

  resources :metadata_types do
    member do
      get :metadata_values
    end

    resources :metadata do
      member do
        patch :toggle_review
        get :tagged_items
        get :delete_confirmation
      end
    end
  end

  root "home#index"
end
