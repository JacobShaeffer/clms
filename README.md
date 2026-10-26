# SolarHub

SolarHub is a Rails application for managing learning content, metadata, libraries, library assets, folders, and user shelves.

## Requirements

- Ruby 4.0.5
- PostgreSQL

The application uses Bootstrap 5.3.8 and import maps. No JavaScript build step is required.

## Setup

1. Install Ruby dependencies:

   ```sh
   bundle install
   ```

2. Create and migrate the database:

   ```sh
   bin/rails db:prepare
   ```

3. Start the application:

   ```sh
   bin/dev
   ```

The development server runs on `http://localhost:3000` by default.

## Database configuration

Development uses PostgreSQL with these defaults:

- Host: `localhost`
- User: `postgres`
- Database: `solarhub_development`

Set `POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` to override them. Use `POSTGRES_TEST_DB` for the test database.

## Demo data

Run the following command to rebuild the development database with demo data:

```sh
bin/rails db:seed
```

This deletes all development records and Active Storage files before loading data. It does not load demo data outside development.

The seed creates one user for each role: `guest`, `organization`, `volunteer`, `intern`, `intern_plus`, and `admin`. Sign in with `role@role.com` and the password `rolerole`; for example, `admin@admin.com` with `adminadmin`.

## Real-world development data

The real-world catalog is stored in `db/real_world_data/contents.csv`. Its associated document archive is intentionally not committed because it expands to approximately 2.5 GB.

Place the archive at `tmp/real_world_documents.zip`, then run:

```sh
SEED_DATA=real_world bin/rails db:seed
```

To read the archive from another location, provide an absolute path:

```sh
SEED_DATA=real_world REAL_WORLD_DOCUMENTS_ZIP=/path/to/documents.zip bin/rails db:seed
```

The real-world seed validates the CSV and archive before deleting existing development data. It creates the standard development users, imported content, metadata, and Active Storage attachments. It does not create shelves or libraries. Size differences between the CSV and ZIP are reported as warnings; missing files and unsupported file types stop the seed before reset.

## Library builds and exports

Version creation and building are independent backend operations. Any locked
version can be built, including an older version. Building never changes the
library's current version. These endpoints use the application's authenticated
session and normal CSRF protection; build access requires an admin.

- `POST /libraries/:library_id/library_versions/:version_id/build` requests a
  build or rebuild and returns `202` with its status and generation.
- `GET /libraries/:library_id/library_versions/:version_id/build` returns the
  latest attempt's status, error, published generation, folder path, and download
  URL. It returns `404` if no build has been requested.
- `GET /libraries/:library_id/library_versions/:version_id/build/download`
  streams the published ZIP. Before the first successful export it returns `409`.

An editable version returns `409` with `error: "version_not_locked"`. After the
user confirms version creation, the existing version endpoint accepts JSON:

```json
{
  "library_version": { "version_number": "2.0" },
  "expected_current_version_id": 123,
  "build_previous_version": true
}
```

Send this to `POST /libraries/:library_id/library_versions` with JSON content
and accept headers. It locks version `123`, creates the editable `2.0` successor,
and requests a build of version `123`. The job is enqueued only after commit.
A stale expected version returns `409`; invalid version numbers return `422`.
Omitting `build_previous_version` creates a version without requesting a build.
The response identifies `new_version`, `locked_version`, and the optional `build`.

Each version has one reusable build record and one published output. States are
`queued`, `exporting`, `ready`, and `failed`. Requests during queued/exporting work
reuse that attempt. A later request increments its generation and replaces the
output only after the replacement passes validation. A failed rebuild leaves
the preceding export downloadable; `published_generation` and `published_at`
identify that export independently of the latest attempt's status. Replaced
outputs are deleted; there is no export history.

Module selections are library-level and available to `intern_plus` and admin
users through `GET` and `PUT /libraries/:library_id/module_selection`. Replace
the selection with `{"module_selection":{"module_ids":[1,2]}}`; use an empty
array to clear it. Deleting a module removes its library selections.

### Export data and SQLite schema

The builder uses the selected version's saved folder names, hierarchy, logo
references, and content placements. Intrinsic content fields, content files,
referenced asset images, the library banner, and module selections use current
Rails values because versioning does not currently preserve them. Historical
file checksums are comparison information and do not restore historical bytes.

**Versioning maintenance:** whenever versioning starts saving another field or
file reference, update `LibraryBuilds::Source` and its tests to prefer that saved
value. Adding versioned fields without updating the builder can export live
values in place of saved values.

Metadata is never snapshotted on the build record or added as columns to
`content`. Each export attempt reads current associated metadata and its types,
without assuming particular taxonomy names. Changes made after queueing and
before execution appear in the export. Finished SQLite files retain the values
written by that attempt.

The output contains:

```text
export/
  library.db
  content/
  assets/
  modules/                 # Only when the library has selected modules
    <module folder name>/  # Empty placeholder, one per selected module
export.zip
```

The ZIP contains the `export/` directory. Content files are copied once per
distinct content ID, regardless of folder count. PDF, MP3, and MP4 are supported.
Assets contain referenced banner, folder-logo, and module-icon PNG images, not
design ZIPs. Filenames include source IDs and sanitized source filenames.

Libraries with selected modules also receive a `modules/` directory alongside
`content/` and `assets/`. It contains one empty directory for each selected module,
named exactly using that module's Folder name field. Empty directories are also
included in the ZIP. No module files are copied yet, and libraries without
selected modules omit `modules/`. Folder names must be distinct within the
selection and must be single directory names. Path separators (`/` and `\\`) and
the names `.` and `..` are not allowed. Invalid names fail the build and leave
any previous export intact.

SQLite schema version `1` is recorded in `PRAGMA user_version`:

- `content`: `id`, `title`, `description`, `file_name`, `file_size` (bytes),
  `year_of_publication`, and `additional_notes`. `title` uses the display title
  with the catalog title as fallback. There are no legacy rights, copyright,
  keyword, or manufactured publication-date columns.
- `folder` and `content_folder` follow the example's hierarchy and placement
  layout. Content filenames are basenames under `content/`; logo paths are
  relative to `export/`.
- `module.module_name` uses the selected module's `folder_name` launch destination.
- `metadata_type`, `metadata`, and `content_metadata` contain current associated
  metadata and its referenced types.
- `content_fts` is a standalone FTS5 table with `rowid = content.id`; it indexes
  `title`, `description`, and `metadata_text` (associated values), with `file_name`
  and `file_size` unindexed. Join search results to `content` by row ID.

This intentionally updates the supplied example's obsolete columns and FTS
definition. SQLite consumers must support this schema.

### Workers and storage

Exports run on the `background` queue using the existing Solid Queue worker.
The production recurring recovery job runs every five minutes and re-enqueues
queued/interrupted attempts untouched for ten minutes. A worker lock prevents
duplicate execution, and generation checks discard obsolete deliveries.
Completed and failed attempts are not automatically rebuilt.

The default export root is `storage/library_exports`, covered by the existing
persistent storage volume. Set `LIBRARY_EXPORT_ROOT` to override it. Web and
worker processes must share this directory on a filesystem supporting `flock`
and atomic rename. Keep it outside the public web root; downloads are authorized
and streamed through the backend. Back it up alongside the application data.

Only one generation is published per version. Private staging and replacement
directories exist temporarily during generation; recovery also removes leftovers
from terminated workers. Source blob references are retained only while an
attempt runs and then detached. Budget disk space for the previous output, the
replacement folder and ZIP, and a temporary source file during copying. Exports
remain on disk until replaced; this feature adds no automatic expiry.

## Tests

Run all tests with:

```sh
bin/rails test
```

## Local server deployment with Kamal

Use Kamal to deploy to a Linux server on the local network. Run Kamal from a workstation with this repository and SSH access to the server. Kamal builds the Docker image, deploys it, checks `/up`, routes traffic through Kamal Proxy, and keeps the previous version until the new version is ready.

### 1. Prepare the server

The server needs a stable local address, SSH access for the deployment user, Docker, PostgreSQL, and a backup location. The deployment user must be able to run Docker. Kamal can install Docker during setup when the SSH user has the required permission.

Allow ports 80 and 443 through the local firewall. Keep PostgreSQL available only to the application server or local network.

### 2. Prepare the database

Create the production PostgreSQL role and databases required by `config/database.yml`. Give the application role access only to those databases.

Set the database host to an address the application container can reach. Do not use `localhost` unless PostgreSQL runs in the same container.

### 3. Configure Kamal

Update `config/deploy.yml` before the first deployment:

- Replace the example server address with the local server address.
- Set the proxy host to the local DNS name, when one is available.
- Set the PostgreSQL connection values under `env.clear`.
- Add the database password under `env.secret`.
- Keep persistent storage mounted for uploaded files.
- Configure a Docker registry reachable by the build machine and deployment server. The current `localhost:5555` setting lets Kamal use a local registry.

### 4. Configure secrets

Keep `RAILS_MASTER_KEY`, database passwords, and registry credentials outside the repository. The `.kamal/secrets` file can read them from environment variables or a password manager. Do not commit raw secrets.

### 5. Deploy

From the project directory, confirm that the deployment server is reachable by SSH. Then run the first deployment:

```sh
bin/kamal setup
```

This prepares the server, starts Kamal Proxy, and deploys the application. The application entrypoint runs `bin/rails db:prepare` when the web server starts.

After the first deployment, release updates with:

```sh
bin/kamal deploy
```

Check the deployment and application logs with:

```sh
bin/kamal details
bin/kamal logs
```

Open the server's `/up` endpoint to confirm the health check. Kamal Proxy sends normal traffic to the application on port 80.

### 6. HTTPS and backups

For an internal HTTP-only service, leave the current SSL settings unchanged. For HTTPS, configure a certificate for Kamal Proxy. Enable `config.assume_ssl` and `config.force_ssl` in `config/environments/production.rb` when SSL terminates at the proxy.

Back up the PostgreSQL databases and persistent upload storage. Test restoring both before relying on the backups.
