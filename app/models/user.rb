class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  has_many :contents
  has_many :metadata_types
  has_many :metadata
  has_many :shelves
  has_many :library_assets
  has_many :libraries
  has_many :library_versions
  has_many :library_folders

  # define user roles
  ROLES = { guest: 0, organization: 1, volunteer: 2, intern: 3, intern_plus: 4, admin: 99 }
  enum :role, ROLES

  # set default user role
  after_initialize :set_default_role

  validates :name, presence: true

  private

  def set_default_role
    self.role ||= :guest
  end
end
