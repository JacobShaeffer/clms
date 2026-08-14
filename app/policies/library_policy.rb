class LibraryPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def show?
    non_guest?
  end

  def all_contents_table?
    show?
  end

  def reset_all_contents_table?
    show?
  end

  def library_contents_table?
    show?
  end

  def reset_library_contents_table?
    show?
  end

  def shelf_contents_table?
    show?
  end

  def reset_shelf_contents_table?
    show?
  end

  def create?
    at_least?(:intern_plus)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.all
    end
  end
end
