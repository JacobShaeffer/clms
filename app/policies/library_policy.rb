class LibraryPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def show?
    non_guest?
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
