# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  private

  def non_guest?
    user.present? && !user.guest?
  end

  def role_level
    return User.roles.fetch("guest") unless user

    User.roles.fetch(user.role, User.roles.fetch("guest"))
  end

  def at_least?(role)
    role_level >= User.roles.fetch(role.to_s)
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope

    def non_guest?
      user.present? && !user.guest?
    end

    def role_level
      return User.roles.fetch("guest") unless user

      User.roles.fetch(user.role, User.roles.fetch("guest"))
    end

    def at_least?(role)
      role_level >= User.roles.fetch(role.to_s)
    end
  end
end
