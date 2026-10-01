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

  def trash_index?
    user&.admin?
  end

  def trash_confirmation?
    trash?
  end

  def trash?
    at_least?(:intern_plus)
  end

  def restore?
    user&.admin?
  end

  def create?
    at_least?(:volunteer)
  end

  def update?
    create?
  end

  def destroy?
    user&.admin?
  end

  def replace_file?
    at_least?(:intern_plus)
  end

  def add_new_metadatum?
    create?
  end

  def add_existing_metadatum?
    index?
  end

  def permitted_attributes
    attributes = [ :title, :display_title, :description, :year_of_publication, :additional_notes ]
    attributes << :file if record == Content || record.new_record? || replace_file?
    attributes << { metadatum_ids: [] }
    attributes
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.active
    end
  end
end
