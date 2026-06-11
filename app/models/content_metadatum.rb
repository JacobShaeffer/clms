class ContentMetadatum < ApplicationRecord
  belongs_to :metadata
  belongs_to :content
end
