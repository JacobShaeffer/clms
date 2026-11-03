module LibraryAssetFiltering
  extend ActiveSupport::Concern

  private

  def set_asset_filters(values, default_asset_type: "")
    values = {} unless values.respond_to?(:permit)
    @query = values[:q].is_a?(String) ? values[:q].strip : ""
    @language = LibraryAsset::LANGUAGES.include?(values[:language]) ? values[:language] : ""
    requested_type = values.key?(:asset_type) ? values[:asset_type] : default_asset_type
    @asset_type = LibraryAsset::ASSET_TYPES.include?(requested_type) ? requested_type : ""
    @asset_filter_context = { q: @query.presence, language: @language.presence, asset_type: @asset_type.presence }.compact
  end

  def filtered_library_assets(scope)
    if @query.present?
      scope = scope.where("library_assets.name ILIKE ?", "%#{LibraryAsset.sanitize_sql_like(@query)}%")
    end
    scope = scope.where(language: @language) if @language.present?
    scope = scope.where(asset_type: @asset_type) if @asset_type.present?
    scope
  end
end
