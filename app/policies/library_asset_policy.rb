class LibraryAssetPolicy < ApplicationPolicy
  def index?
    at_least?(:intern_plus)
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def update?
    index?
  end

  def destroy?
    index?
  end

  def delete_confirmation?
    destroy?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless at_least?(:intern_plus)

      scope.all
    end
  end
end
