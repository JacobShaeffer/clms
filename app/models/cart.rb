class Cart < ApplicationRecord
  belongs_to :user

  has_many :carts_contents, dependent: :destroy
  has_many :contents, through: :carts_contents
end
