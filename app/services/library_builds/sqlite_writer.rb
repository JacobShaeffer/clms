require "sqlite3"

module LibraryBuilds
  class SqliteWriter
    SCHEMA_VERSION = 1
    SCHEMA = <<~SQL
      CREATE TABLE content (
        id INTEGER PRIMARY KEY, title TEXT NOT NULL, description TEXT,
        file_name TEXT NOT NULL, file_size INTEGER NOT NULL,
        year_of_publication INTEGER, additional_notes INTEGER
      );
      CREATE TABLE folder (
        id INTEGER PRIMARY KEY, folder_name TEXT NOT NULL, logo TEXT,
        parent_id INTEGER REFERENCES folder(id) DEFERRABLE INITIALLY DEFERRED
      );
      CREATE TABLE content_folder (
        id INTEGER NOT NULL REFERENCES content(id), folder_id INTEGER NOT NULL REFERENCES folder(id),
        title TEXT, file_name TEXT, file_size INTEGER, PRIMARY KEY (id, folder_id)
      );
      CREATE INDEX content_folder_folder ON content_folder(folder_id);
      CREATE TABLE module (id INTEGER PRIMARY KEY, module_name TEXT NOT NULL, logo TEXT);
      CREATE TABLE metadata_type (id INTEGER PRIMARY KEY, type_name TEXT NOT NULL);
      CREATE TABLE metadata (
        id INTEGER PRIMARY KEY, meta_name TEXT NOT NULL, type_name TEXT NOT NULL,
        type_id INTEGER NOT NULL REFERENCES metadata_type(id)
      );
      CREATE INDEX metadata_type_lookup ON metadata(type_id);
      CREATE TABLE content_metadata (
        content_id INTEGER NOT NULL REFERENCES content(id), metadata_id INTEGER NOT NULL REFERENCES metadata(id),
        PRIMARY KEY (content_id, metadata_id)
      );
      CREATE INDEX content_metadata_value ON content_metadata(metadata_id);
      CREATE VIRTUAL TABLE content_fts USING fts5(
        title, file_name UNINDEXED, description, file_size UNINDEXED, metadata_text
      );
    SQL

    def self.call(source:, path:)
      new(source:, path:).call
    end

    def initialize(source:, path:)
      @source, @path = source, path
    end

    def call
      db = SQLite3::Database.new(path.to_s)
      db.execute("PRAGMA foreign_keys = ON")
      db.transaction do
        db.execute_batch(SCHEMA)
        insert(db, "content", source.contents)
        insert(db, "folder", source.folders)
        contents = source.contents.index_by { |row| row[:id] }
        insert(db, "content_folder", source.placements.map do |row|
          contents.fetch(row[:id]).slice(:title, :file_name, :file_size).merge(row)
        end)
        insert(db, "module", source.modules)
        insert(db, "metadata_type", source.metadata_types)
        insert(db, "metadata", source.metadata)
        insert(db, "content_metadata", source.content_metadata)

        values = source.metadata.index_by { |row| row[:id] }
        links = source.content_metadata.group_by { |row| row[:content_id] }
        insert(db, "content_fts", source.contents.map do |row|
          terms = links.fetch(row[:id], []).map { |link| values.fetch(link[:metadata_id])[:meta_name] }.join(" ")
          row.slice(:title, :file_name, :description, :file_size).merge(rowid: row[:id], metadata_text: terms)
        end)
        db.execute("PRAGMA user_version = #{SCHEMA_VERSION}")
      end
      raise Error, "SQLite integrity check failed" unless db.execute("PRAGMA integrity_check") == [ [ "ok" ] ]
      raise Error, "SQLite foreign key check failed" unless db.execute("PRAGMA foreign_key_check").empty?

      db.execute("INSERT INTO content_fts(content_fts) VALUES ('integrity-check')")
      path
    ensure
      db&.close
    end

    private

    attr_reader :source, :path

    def insert(db, table, rows)
      return if rows.empty?

      columns = rows.first.keys
      sql = "INSERT INTO #{table} (#{columns.join(',')}) VALUES (#{Array.new(columns.length, '?').join(',')})"
      db.prepare(sql) do |statement|
        rows.each { |row| statement.execute!(*row.values_at(*columns)) }
      end
    end
  end
end
