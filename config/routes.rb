Rails.application.routes.draw do
  resources :libraries, only: %i[ index show new create ] do
    resources :library_folders, only: %i[ new create ]
    resources :library_versions, only: %i[ new create ]
    resource :folder_selection, controller: "library_folder_selections", only: [] do
      get :remove_confirmation
      delete :remove
      get :move
      patch :apply_move
      get :duplicate
      post :apply_duplicate
    end

    member do
      get :all_contents_table
      delete :reset_all_contents_table
      get :library_contents_table
      delete :reset_library_contents_table
      get :shelf_contents_table
      delete :reset_shelf_contents_table
      post :add_to_active_folder
    end
  end

  resources :library_assets do
    member do
      get :delete_confirmation
    end
  end
  devise_for :users

  resources :contents, only: %i[ index new create ] do
    collection do
      post :validate_file
      get :table
      delete :reset_table
      post :add_to_shelves
      get :search
      post :add_new_metadatum
      get :add_existing_metadatum
    end
  end

  resources :shelves, only: %i[ index new create ] do
    member do
      get :table
      patch :activate
      patch :archive
      patch :move
      delete :reset_table
    end
  end

  resources :metadata_types do
    collection do
      get :edit_all
      patch :update_all
    end

    member do
      get :metadata_values
    end

    resources :metadata do
      member do
        patch :toggle_review
        get :tagged_items
        get :replace_confirmation
        patch :replace
        get :delete_confirmation
      end
    end
  end

  root "home#index"
end
