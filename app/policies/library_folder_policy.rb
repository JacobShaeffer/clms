class LibraryFolderPolicy < ApplicationPolicy
  def create?
    at_least?(:intern_plus)
  end

  def manage?
    create?
  end

  def update?
    manage?
  end
end
