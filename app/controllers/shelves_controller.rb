class ShelvesController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize Shelf

    load_shelf_lists
    load_selected_shelf if params[:selected_shelf_id].present?
    load_contents_table if @selected_shelf
  end

  def new
    @shelf = current_user.shelves.build
    authorize @shelf
    load_selected_shelf if params[:selected_shelf_id].present?

    render partial: "shelves/modal_form", locals: { shelf: @shelf } if turbo_frame_request?
  end

  def create
    @shelf = current_user.shelves.build
    authorize @shelf
    @shelf.assign_attributes(shelf_params)
    load_selected_shelf if params[:selected_shelf_id].present?

    created = false
    Shelf.transaction do
      if @shelf.save
        ActiveShelf.prepend!(user: current_user, shelf: @shelf)
        created = true
      else
        raise ActiveRecord::Rollback
      end
    end

    respond_to do |format|
      if created
        load_shelf_lists
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("modal", ""),
            turbo_stream.replace("shelf-lists", partial: "shelves/shelf_lists")
          ]
        end
        format.html do
          redirect_to shelves_path(selected_shelf_id: @selected_shelf&.id),
            notice: "Shelf was successfully created.",
            status: :see_other
        end
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "modal",
            partial: "shelves/modal_form",
            locals: { shelf: @shelf }
          ), status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def table
    load_shelf
    authorize @shelf
    @selected_shelf = @shelf
    load_contents_table

    render partial: "content_tables/table_frame", locals: table_locals
  end

  def activate
    load_shelf
    authorize @shelf
    ActiveShelf.activate!(user: current_user, shelf: @shelf)

    redirect_to shelves_path(selected_shelf_id: @shelf.id), status: :see_other
  rescue ActiveShelf::LimitReached => error
    redirect_to shelves_path(selected_shelf_id: @shelf.id), alert: error.message, status: :see_other
  end

  def archive
    load_shelf
    authorize @shelf
    ActiveShelf.archive!(user: current_user, shelf: @shelf)

    redirect_to shelves_path(selected_shelf_id: @shelf.id), status: :see_other
  end

  def move
    load_shelf
    authorize @shelf
    ActiveShelf.move!(user: current_user, shelf: @shelf, direction: params[:direction])

    redirect_to shelves_path(selected_shelf_id: @shelf.id), status: :see_other
  rescue ArgumentError => error
    redirect_to shelves_path(selected_shelf_id: @shelf.id), alert: error.message, status: :see_other
  end

  def reset_table
    load_shelf
    authorize @shelf
    current_user.content_table_preferences.find_by(
      table_key: ContentTables::ShelfContentsDefinition.state_key_for(@shelf)
    )&.destroy!

    redirect_to shelves_path(selected_shelf_id: @shelf.id), status: :see_other
  end

  private

  def load_shelf_lists
    @shelves = policy_scope(Shelf).order(:name, :id)
    @active_shelf_records = current_user.active_shelves.includes(:shelf).ordered.to_a
    @active_shelves = @active_shelf_records.map(&:shelf)
    @archived_shelves = @shelves.where.not(id: @active_shelves.map(&:id))
  end

  def load_shelf
    @shelf = policy_scope(Shelf).find(params[:id])
  end

  def load_selected_shelf
    @selected_shelf = policy_scope(Shelf).find(params[:selected_shelf_id])
  end

  def load_contents_table
    metadata_types = policy_scope(MetadataType).order(:order, :name)
    source = policy_scope(Content)
      .where(id: @selected_shelf.contents.select(:id))
      .includes(:user, :shelves, metadata: :metadata_type)
    @table_definition = ContentTables::ShelfContentsDefinition.new(
      user: current_user,
      shelf: @selected_shelf,
      source:,
      metadata_types:,
      update_path: table_shelf_path(@selected_shelf),
      reset_path: reset_table_shelf_path(@selected_shelf)
    )
    table = ContentTables::Coordinator.call(
      user: current_user,
      definition: @table_definition,
      params:,
      paginator: method(:paginate_contents)
    )
    @table_state = table.state
    @pagy = table.pagy
    @contents = table.records
  end

  def paginate_contents(relation:, page:, per_page:)
    pagy(:offset, relation, limit: per_page, page:)
  end

  def table_locals
    {
      definition: @table_definition,
      state: @table_state,
      records: @contents,
      pagy: @pagy
    }
  end

  def shelf_params
    params.require(:shelf).permit(policy(@shelf).permitted_attributes)
  end
end
