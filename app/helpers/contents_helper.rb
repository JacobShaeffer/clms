module ContentsHelper
  def content_column_value(content, key)
    case key
    when "id"
      content.id
    when "title"
      content.title
    when "display_title"
      content.display_title
    when "description"
      content.description
    when "year_of_publication"
      content.year_of_publication
    when "additional_notes"
      content.additional_notes
    when "created_at"
      formatted_content_date(content.created_at)
    when "updated_at"
      formatted_content_date(content.updated_at)
    when "added_by"
      content.user&.name.presence || content.user&.email
    end
  end

  def content_table_value(value)
    value.present? ? value : tag.span("None", class: "text-muted")
  end

  private

  def formatted_content_date(value)
    value&.strftime("%Y-%m-%d")
  end
end
