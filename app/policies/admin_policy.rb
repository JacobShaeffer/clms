class AdminPolicy < ApplicationPolicy
  def index?
    user&.admin? && user.active?
  end
end
