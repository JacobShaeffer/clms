class LibraryModuleSelection < ApplicationRecord
  belongs_to :library
  belongs_to :library_module

  validates :library_module_id, uniqueness: { scope: :library_id }
end
