class LibraryFolderPolicy < ApplicationPolicy
  def create?
    at_least?(:intern_plus)
  end
end
