module MetadataTypesHelper
  def metadata_access_level_options
    User.roles.map { |name, value| [ name.humanize, value ] }
  end
end
