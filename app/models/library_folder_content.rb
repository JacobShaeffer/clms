class LibraryFolderContent < ApplicationRecord
  belongs_to :library_folder
  belongs_to :content

  validates :content_id, uniqueness: { scope: :library_folder_id }
end
