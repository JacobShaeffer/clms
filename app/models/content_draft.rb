class ContentDraft < ApplicationRecord
  belongs_to :user
  has_one_attached :file

  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }

  def capture!(content:, attributes:, submission_errors: [])
    self.form_data = attributes.except("file")
    self.submission_errors = submission_errors
    self.updated_at = Time.current
    self.file = content.file.blob if content.file.attached?
    save!
  end

  def build_content(metadata_scope: Metadatum.all)
    user.contents.build(form_data.except("metadatum_ids")).tap do |content|
      content.metadatum_ids = metadata_scope.where(id: form_data["metadatum_ids"]).pluck(:id)
      content.file = file.blob if file.attached?
    end
  end

  def display_name
    form_data["title"].presence || (file.filename.to_s if file.attached?) || I18n.l(updated_at, format: :long)
  end
end
