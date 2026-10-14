class CreateContentDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :content_drafts do |t|
      t.references :user, null: false, foreign_key: true
      t.jsonb :form_data, null: false, default: {}
      t.jsonb :submission_errors, null: false, default: []
      t.timestamps
    end
  end
end
