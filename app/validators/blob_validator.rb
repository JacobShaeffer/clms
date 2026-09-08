class BlobValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return unless value.attached?

    validate_file_type(record, attribute, value.blob)
    validate_size(record, attribute, value.blob)
  end

  private

  def validate_file_type(record, attribute, blob)
    allowed_content_types = Array(options[:content_type])
    allowed_extensions = Array(options[:extension])
    content_type_valid = allowed_content_types.blank? || allowed_content_types.include?(blob.content_type)
    extension_valid = allowed_extensions.blank? || allowed_extensions.include?(File.extname(blob.filename.to_s).downcase)
    return if content_type_valid && extension_valid

    record.errors.add(attribute, "must be a supported file type")
  end

  def validate_size(record, attribute, blob)
    size_range = options[:size_range]
    return if size_range.blank? || size_range.cover?(blob.byte_size)

    record.errors.add(attribute, "must be within the allowed file size")
  end
end
