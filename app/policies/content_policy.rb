class ContentPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def table?
    index?
  end

  def reset_table?
    index?
  end

  def add_to_shelves?
    index?
  end

  def search?
    index?
  end

  def show?
    non_guest?
  end

  def create?
    at_least?(:volunteer)
  end

  def add_new_metadatum?
    create?
  end

  def add_existing_metadatum?
    create?
  end

  def permitted_attributes
    [ :title, :display_title, :description, :year_of_publication, :additional_notes, :file, { metadatum_ids: [] } ]
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.all
    end
  end
end
