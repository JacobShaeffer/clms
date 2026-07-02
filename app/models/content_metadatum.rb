class ContentMetadatum < ApplicationRecord
  self.table_name = "contents_metadata"

  belongs_to :metadata, class_name: "Metadatum", foreign_key: "metadata_id"
  belongs_to :content
end
