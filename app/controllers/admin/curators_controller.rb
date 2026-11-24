class Admin::CuratorsController < Admin::BaseController
  before_action :load_period

  def stats
    return unless @period.ready?

    @users = User.order(:name, :id)
    source = Content.active.where(created_at: @period.range)
    @counts = { "all" => source.group(:user_id).count }
    %w[warning danger].each do |severity|
      @counts[severity] = issue_filter.apply(relation: source, values: { "value" => severity }, column: nil).group(:user_id).count
    end
  end

  def content
    return unless @period.ready?

    @users = User.order(:name, :id)
    source = Content.active.where(created_at: @period.range).includes(:user, :file_attachment, metadata: :metadata_type)
    if params[:user_id].present?
      user_id = Integer(params[:user_id].to_s, exception: false)
      source = user_id ? source.where(user_id: user_id) : source.none
    end
    if %w[warning danger].include?(params[:severity])
      source = issue_filter.apply(relation: source, values: { "value" => params[:severity] }, column: nil)
    end
    @pagy, @contents = pagy(:offset, source.order(created_at: :desc, id: :desc), limit: 25)
    @metadata_types = MetadataType.order(:order, :name).to_a
    @table_definition = ContentTables::ContentsDefinition.new(
      source: source, metadata_types: @metadata_types,
      update_path: admin_curator_content_path, reset_path: admin_curator_content_path,
      dom_prefix: "admin-curator-content", selectable: false
    )
  end

  private

  def load_period
    @period = Admin::ReportPeriod.new(params)
  end

  def issue_filter
    @issue_filter ||= ContentTables::Filters::Issues.new(metadata_types: MetadataType.order(:order, :name).to_a)
  end
end
