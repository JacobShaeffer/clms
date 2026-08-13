class ShelfContent < ApplicationRecord
  belongs_to :shelf
  belongs_to :content
end
