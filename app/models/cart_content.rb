class CartContent < ApplicationRecord
  belongs_to :cart
  belongs_to :content
end
