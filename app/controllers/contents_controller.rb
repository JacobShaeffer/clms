class ContentsController < ApplicationController
  PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
  DEFAULT_PER_PAGE = 10

  before_action :authenticate_user!

  def index
    authorize Content

    @search_query = params[:q].to_s
    @per_page_options = PER_PAGE_OPTIONS
    @per_page = normalized_per_page
    @metadata_types = policy_scope(MetadataType).order(:order, :name).limit(2)

    contents = filtered_contents
    @pagy, @contents = pagy(:offset, contents, limit: @per_page)
  end

  def new
    @content = current_user.contents.build
    authorize @content

    render partial: "contents/modal_form", locals: { content: @content } if turbo_frame_request?
  end

  def create
    @content = current_user.contents.build
    authorize @content
    @content.assign_attributes(content_params)

    if @content.save
      redirect_to contents_path, notice: "Content was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def filtered_contents
    contents = policy_scope(Content)
      .includes(:user, metadata: :metadata_type)
      .order(created_at: :desc)

    return contents if @search_query.blank?

    query = ActiveRecord::Base.sanitize_sql_like(@search_query)
    contents.where("contents.title LIKE ?", "%#{query}%")
  end

  def normalized_per_page
    per_page = params[:per_page].to_i

    PER_PAGE_OPTIONS.include?(per_page) ? per_page : DEFAULT_PER_PAGE
  end

  def content_params
    params.require(:content).permit(policy(@content).permitted_attributes)
  end
end
