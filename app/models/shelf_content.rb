class ShelfContent < ApplicationRecord
  belongs_to :shelf
  belongs_to :content

  validates :content_id, uniqueness: { scope: :shelf_id }
end
