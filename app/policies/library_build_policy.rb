class LibraryBuildPolicy < ApplicationPolicy
  def create?
    user&.admin?
  end

  def show?
    create?
  end

  def download?
    show?
  end
end
