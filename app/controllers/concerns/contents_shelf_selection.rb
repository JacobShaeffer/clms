module ContentsShelfSelection
  extend ActiveSupport::Concern

  ADD_TO_SHELVES_FORM_ID = "contents-add-to-shelves-form"
  ADD_TO_SHELVES_STATUS_ID = "contents-add-to-shelves-status"

  private

  def load_contents_index_table
    metadata_types = policy_scope(MetadataType).order(:order, :name)
    source = policy_scope(Content).includes(:user, metadata: :metadata_type)
    @table_definition = ContentTables::ContentsDefinition.new(
      source:,
      metadata_types:,
      update_path: table_contents_path,
      reset_path: reset_table_contents_path,
      selection_form_id: ADD_TO_SHELVES_FORM_ID
    )
    session.delete("contents_index_state")
    table = ContentTables::Coordinator.call(
      user: current_user,
      definition: @table_definition,
      params:,
      paginator: method(:paginate_contents)
    )
    @table_state = table.state
    @pagy = table.pagy
    @contents = table.records
    @navigation_token = table.navigation_token
  end

  def load_active_shelves
    @active_shelves = current_user.active_shelves.includes(:shelf).ordered.map(&:shelf)
  end

  def render_add_to_shelves_success(message, close_modal: false)
    load_active_shelves
    load_contents_index_table

    streams = [
      turbo_stream.replace(
        @table_definition.frame_id,
        partial: "content_tables/table_frame",
        locals: table_locals
      ),
      turbo_stream.replace(
        ADD_TO_SHELVES_FORM_ID,
        partial: "contents/add_to_shelves_form",
        locals: { definition: @table_definition, active_shelves: @active_shelves }
      ),
      turbo_stream.update(
        ADD_TO_SHELVES_STATUS_ID,
        partial: "contents/add_to_shelves_status",
        locals: { message:, type: :success }
      )
    ]
    streams.unshift(turbo_stream.update("modal", "")) if close_modal

    render turbo_stream: streams
  end
end
