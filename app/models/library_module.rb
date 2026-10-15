class LibraryModule < ApplicationRecord
  belongs_to :user
  belongs_to :icon, class_name: "LibraryAsset", inverse_of: :library_modules

  validates :name, presence: true
  validates :folder_name, presence: true
end
