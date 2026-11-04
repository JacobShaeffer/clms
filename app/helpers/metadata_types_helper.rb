module MetadataTypesHelper
  def metadata_access_level_options
    User.roles.map { |name, value| [ name.titleize, value ] }
  end
end
