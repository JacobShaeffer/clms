class Shelf < ApplicationRecord
  belongs_to :user

  has_many :shelf_contents, dependent: :destroy
  has_many :contents, through: :shelf_contents
  has_one :active_shelf, dependent: :destroy
end
