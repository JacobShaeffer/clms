class LibraryModuleSelectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library

  rescue_from Pundit::NotAuthorizedError do
    render json: { error: "forbidden" }, status: :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  def show
    render json: selection_payload
  end

  def update
    values = params.expect(module_selection: [ module_ids: [] ])
    ids = values[:module_ids]
    unless ids.is_a?(Array) && ids.all? { |id| Integer(id.to_s, exception: false)&.positive? }
      return render json: { error: "invalid_module_ids" }, status: :unprocessable_content
    end

    ids = ids.map(&:to_i).uniq
    @library.with_lock do
      modules = policy_scope(LibraryModule).where(id: ids).order(:id).lock.to_a
      unless modules.length == ids.length
        return render json: { error: "unavailable_modules" }, status: :unprocessable_content
      end

      @library.selected_modules = modules
    end
    render json: selection_payload
  end

  private

  def set_library
    authorize Library, :module_selection?
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def selection_payload
    { library_id: @library.id, module_ids: @library.selected_modules.order(:id).ids }
  end
end
