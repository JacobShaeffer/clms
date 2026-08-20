class DefaultMetadataTypeAccessLevelToOrganization < ActiveRecord::Migration[8.1]
  def change
    change_column_default :metadata_types,
      :access_level,
      from: 0,
      to: 1
  end
end
