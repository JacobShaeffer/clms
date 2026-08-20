json.extract! metadata_type, :id, :name, :order, :access_level, :created_at, :updated_at
json.url metadata_type_url(metadata_type, format: :json)
