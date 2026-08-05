class Cart < ApplicationRecord
  belongs_to :user

  has_many :cart_contents, dependent: :destroy
  has_many :contents, through: :cart_contents
end
