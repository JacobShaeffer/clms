Rails.application.routes.draw do
  resources :libraries, only: %i[ index show new create ]

  resources :library_assets do
    member do
      get :delete_confirmation
    end
  end
  devise_for :users

  resources :contents, only: %i[ index new create ] do
    collection do
      get :table
      get :search
      post :add_new_metadatum
      get :add_existing_metadatum
    end
  end

  resources :shelves, only: :index

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
