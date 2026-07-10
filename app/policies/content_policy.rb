class ContentPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def table?
    index?
  end

  def show?
    non_guest?
  end

  def create?
    at_least?(:volunteer)
  end

  def permitted_attributes
    [ :title, :display_title, :description, :year_of_publication, :additional_notes, :file ]
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.all
    end
  end
end
