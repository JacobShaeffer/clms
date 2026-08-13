class ShelvesController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize Shelf

    @shelves = policy_scope(Shelf).order(:name, :id)
  end
end
