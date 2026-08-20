class MetadataType < ApplicationRecord
  belongs_to :user
  has_many :metadata, dependent: :destroy

  validates :name, presence: true, allow_blank: false, uniqueness: { case_sensitive: false, message: "Name must be unique" }
  validates :access_level, inclusion: { in: User.roles.values }
  validates :order, numericality: { only_integer: true }

  scope :in_display_order, -> { order(:order, :name, :id) }
end
