# SolarHub to SPELL Hub transition

The application now displays **SPELL Hub**, uses the Ruby namespace `SPELLHub`,
and uses `spellhub` for database and Docker names. Existing routes and data
formats are preserved. The namespace change gives Rails a new session cookie;
sign in again after the transition.

This runbook preserves the original PostgreSQL volume and restores logical
backups into `spellhub_postgres_data`. Production has not been deployed; its
configuration and [setup guide](spellhub-postgresql-setup.pdf) use the new names.

## Before starting

Run these commands in **Bash on the host**, outside the dev container. Stopping
the existing app container disconnects its terminals and the current VS Code
session. The observed host checkout is `~/Documents/code/clms`.

Save the rename changes in a commit first. Keep the same Bash terminal open
through the cutover so its variables and functions remain available. Docker
Desktop must be running. Allow disk space for a complete checkout backup
(including uploads and the approximately 2.2 GB source ZIP) and a second database
volume. The backup contains local secrets; keep it private.
The checksum commands use `shasum`, included with macOS.

If `REAL_WORLD_DOCUMENTS_ZIP` points outside the checkout, back up that archive
separately as well. Also back up any external `LIBRARY_EXPORT_ROOT`. Update
absolute source/archive and export-root overrides that reference the old host
or container folder after the move.

**Restore and verify the databases before reopening VS Code in the new
container.** Its automatic `bin/setup --skip-server` runs `db:prepare`. An empty
development database causes this application's destructive seed routines to run
and initialize demo data. Restoring first preserves the original database and
storage pairing. Changing `POSTGRES_DB` alone does not rename an existing database.

The implementation saved the original Git revision and configuration under
`.backups/platform-rename/`. The commands also recover the tracked configuration
from the pre-rename revision recorded below, so they work when that ignored
directory has not been copied to the host. Do not remove the existing Docker
resources yet.

## 1. Record recovery information

```bash
bash
set -euo pipefail
umask 077
cd "$HOME/Documents/code/clms"
command -v shasum > /dev/null

test -z "$(git status --porcelain)" || {
  printf '%s\n' 'Commit or save working changes before continuing.' >&2
  exit 1
}
transition_old_checkout=$(pwd -P)
transition_checkout=$transition_old_checkout
transition_new_checkout="$(dirname "$transition_checkout")/spellhub"
test ! -e "$transition_new_checkout"
if docker volume inspect spellhub_postgres_data > /dev/null 2>&1; then
  printf '%s\n' 'spellhub_postgres_data already exists; stop and inspect it.' >&2
  exit 1
fi
transition_original_revision=a472efed35a794af68952b63788c0af4bca984a5
git cat-file -e "${transition_original_revision}^{commit}"
transition_backup=$(mktemp -d "$(dirname "$transition_checkout")/spellhub-transition.XXXXXX")
mkdir -p .backups/platform-rename
printf '%s\n' "$transition_backup" > .backups/platform-rename/last-backup
printf '%s\n' "$transition_old_checkout" > "$transition_backup/original-checkout"
printf '%s\n' "$transition_original_revision" > "$transition_backup/original-revision"
git rev-parse HEAD > "$transition_backup/rename-revision"
cp -R .backups/platform-rename "$transition_backup/original-config"
mkdir -p "$transition_backup/original-config/.devcontainer" "$transition_backup/original-config/config"
for transition_config in .devcontainer/compose.yaml .devcontainer/devcontainer.json \
  config/application.rb config/database.yml config/deploy.yml; do
  git show "$transition_original_revision:$transition_config" \
    > "$transition_backup/original-config/$transition_config"
done
docker inspect solarhub-rails-app-1 solarhub-postgres-1 solarhub-selenium-1 \
  > "$transition_backup/original-containers.json"
docker volume inspect solarhub_postgres_data > "$transition_backup/original-volume.json"
docker compose --project-name solarhub \
  --project-directory "$transition_checkout/.devcontainer" \
  -f "$transition_backup/original-config/.devcontainer/compose.yaml" config \
  > "$transition_backup/original-compose.resolved.yaml"
transition_app_image=$(docker inspect --format '{{.Image}}' solarhub-rails-app-1)
printf '%s\n' "$transition_app_image" > "$transition_backup/original-app-image"
printf 'Recovery directory: %s\n' "$transition_backup"
```

## 2. Stop writes and back up

Stop any external writers to these databases as well. The commands below stop
the entire development app container, including any web, worker, and test
processes, while leaving PostgreSQL available for backups.

```bash
docker stop solarhub-rails-app-1 solarhub-selenium-1

docker exec solarhub-postgres-1 psql -XAt -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "SELECT datname FROM pg_database WHERE datname ~ '^solarhub_[a-z0-9_]+$' ORDER BY datname" \
  > "$transition_backup/databases.txt"
test -s "$transition_backup/databases.txt"
docker exec solarhub-postgres-1 psql -X --csv -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "SELECT datname, pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname ~ '^solarhub_[a-z0-9_]+$' ORDER BY datname" \
  > "$transition_backup/database-owners.csv"
cat "$transition_backup/database-owners.csv"

cat > "$transition_backup/table-counts.sql" <<'SQL'
SELECT format('SELECT %L || ''|'' || count(*)::text FROM %I.%I',
              schemaname || '.' || tablename, schemaname, tablename)
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename
\gexec
SQL

while IFS= read -r transition_db; do
  docker exec -i solarhub-postgres-1 psql -XAt -v ON_ERROR_STOP=1 -U postgres \
    -d "$transition_db" < "$transition_backup/table-counts.sql" \
    > "$transition_backup/$transition_db.counts"
  docker exec solarhub-postgres-1 pg_dump -U postgres --format=custom \
    --dbname="$transition_db" > "$transition_backup/$transition_db.dump"
  docker exec -i solarhub-postgres-1 pg_restore --list \
    < "$transition_backup/$transition_db.dump" > /dev/null
done < "$transition_backup/databases.txt"

transition_storage_manifest() {
  (
    cd "$transition_checkout"
    find storage -type f -exec shasum -a 256 '{}' + | LC_ALL=C sort
  )
}
transition_storage_manifest > "$transition_backup/storage-before.sha256"

# Include .git, local secrets, uploads, exports, and source-data inputs.
# Keep the archive outside the checkout and outside directories cleared by setup.
tar --exclude='./.backups' --exclude='./log' --exclude='./tmp/cache' \
  --exclude='./tmp/pids' --exclude='./tmp/sockets' \
  -cf "$transition_backup/worktree.tar" .
tar -tf "$transition_backup/worktree.tar" > "$transition_backup/worktree-files.txt"
docker stop solarhub-postgres-1
```

The observed databases are development, test, and test workers `_0` through `_7`.
The loop inventories the current databases rather than assuming that count.
All observed databases are owned by `postgres`. If the owner inventory differs,
stop and arrange the corresponding roles before restoring. The development
snapshot previously contained 6 users, 108 contents, and 114 blobs; the saved
counts, taken after stopping writers, are the acceptance baseline.

## 3. Rename the checkout and restore into the new volume

These commands fail if the target volume already exists, protecting an earlier
attempt or another installation. On failure, retain both environments and use
the rollback section; do not retry by deleting data.

```bash
cd "$(dirname "$transition_checkout")"
mv "$transition_old_checkout" "$transition_new_checkout"
transition_checkout=$transition_new_checkout
cd "$transition_checkout"

if docker volume inspect spellhub_postgres_data > /dev/null 2>&1; then
  printf '%s\n' 'spellhub_postgres_data already exists; stop and inspect it.' >&2
  exit 1
fi
docker compose --project-name spellhub -f .devcontainer/compose.yaml up -d postgres

transition_attempt=0
until docker exec spellhub-postgres-1 pg_isready -h 127.0.0.1 -U postgres -d postgres > /dev/null 2>&1; do
  transition_attempt=$((transition_attempt + 1))
  test "$transition_attempt" -lt 60 || {
    printf '%s\n' 'PostgreSQL did not become ready; inspect its logs.' >&2
    exit 1
  }
  sleep 1
done

while IFS= read -r transition_db; do
  transition_target="spellhub_${transition_db#solarhub_}"
  # The fresh PostgreSQL image creates only spellhub_development itself.
  if [ "$transition_target" != spellhub_development ]; then
    docker exec spellhub-postgres-1 createdb -U postgres --owner=postgres \
      --template=template0 "$transition_target"
  fi
  docker exec -i spellhub-postgres-1 pg_restore -U postgres \
    --exit-on-error --single-transaction --no-owner --dbname="$transition_target" \
    < "$transition_backup/$transition_db.dump"
  docker exec -i spellhub-postgres-1 psql -XAt -v ON_ERROR_STOP=1 -U postgres \
    -d "$transition_target" < "$transition_backup/table-counts.sql" \
    > "$transition_backup/$transition_target.counts"
  diff -u "$transition_backup/$transition_db.counts" "$transition_backup/$transition_target.counts"
done < "$transition_backup/databases.txt"

transition_storage_manifest > "$transition_backup/storage-after.sha256"
diff -u "$transition_backup/storage-before.sha256" "$transition_backup/storage-after.sha256"
docker exec spellhub-postgres-1 psql -XAt -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "SELECT datname FROM pg_database WHERE datname ~ '^(solarhub|spellhub)_' ORDER BY datname"
```

Do not pass `--create` to `pg_restore`: that option restores into the database
name stored in the archive, even when `--dbname` specifies a different name.
Restore into the explicitly created new names instead. See
[PostgreSQL's restore documentation](https://www.postgresql.org/docs/16/app-pgrestore.html).

The new cluster must contain the mapped `spellhub_*` names and no `solarhub_*`
databases. Every count and storage comparison must pass before continuing.

## 4. Reopen VS Code and accept the transition

Open `~/Documents/code/spellhub` in a local VS Code window, then select
**Dev Containers: Reopen in Container**. The new Compose project recreates the
app and Selenium containers under `spellhub`; its PostgreSQL service reuses the
restored `spellhub_postgres_data` volume. A container rename alone would not
update Compose ownership, mounts, or environment values.

The new container should display **SPELL Hub**, open `/workspaces/spellhub`, and
set `POSTGRES_DB=spellhub_development` and `POSTGRES_TEST_DB=spellhub_test`.
Review any shell, VS Code, `.env`, `DATABASE_URL`, or `POSTGRES_*` overrides for
old database names before starting Rails. Preserve master keys and passwords.
The generic VS Code extension volume and existing editor settings can be reused;
reinstalling VS Code is unnecessary. See the
[VS Code dev container guide](https://code.visualstudio.com/docs/devcontainers/create-dev-container).

In the new container:

```bash
pwd
bin/rails runner 'puts Rails.application.class.name; puts ActiveRecord::Base.connection_db_config.database'
bin/rails zeitwerk:check
bin/rails test test/controllers/bootstrap_styling_test.rb
bin/rails test
PARALLEL_WORKERS=1 bin/rails test:system
bin/dev
```

Confirm the title and navbar show **SPELL Hub**. Sign in, download an existing
attachment, upload and download a new attachment, and download an existing
published library export when one exists. The table-count and storage comparisons
above are taken before these operations or tests change data. Keep the backup
and stopped old Docker resources until these checks pass.

The development Selenium container supports one browser session, so run system
tests with one worker. The regular Rails suite can still run in parallel.

The first future production deployment uses Kamal service/image `spellhub`,
volume `spellhub_storage`, role `spellhub`, and the four `spellhub_production*`
databases described in the production setup guide.

## Rollback

Run rollback from a **host Bash terminal**, after saving any new development
work and stopping all writers. Preserve post-cutover work separately: the old
database volume represents the pre-cutover snapshot.

If the checkout has not been renamed yet, recovery only requires
`docker start solarhub-postgres-1 solarhub-selenium-1 solarhub-rails-app-1`.
The following procedure applies after the checkout has moved to `spellhub`.

If starting a new terminal, recover the backup path from
`spellhub/.backups/platform-rename/last-backup`, then set the variables below.
Replace the example backup path with the recorded recovery directory.

```bash
set -euo pipefail
umask 077
transition_backup='/absolute/path/to/spellhub-transition.XXXXXX'
transition_old_checkout=$(cat "$transition_backup/original-checkout")
transition_new_checkout="$(dirname "$transition_old_checkout")/spellhub"
transition_original_revision=$(cat "$transition_backup/original-revision")

cd "$transition_new_checkout"
test -z "$(git status --porcelain)" || {
  printf '%s\n' 'Save post-cutover changes before switching revisions.' >&2
  exit 1
}
docker compose --project-name spellhub -f .devcontainer/compose.yaml stop
git switch --detach "$transition_original_revision"
test ! -e "$transition_old_checkout"
cd "$(dirname "$transition_new_checkout")"
mv "$transition_new_checkout" "$transition_old_checkout"
cd "$transition_old_checkout"

# Preserve new uploads/exports, then restore the exact original storage tree.
test ! -e "$transition_backup/storage-after-cutover"
mv storage "$transition_backup/storage-after-cutover"
tar -xf "$transition_backup/worktree.tar" ./storage
docker start solarhub-postgres-1 solarhub-selenium-1 solarhub-rails-app-1
```

Reopen the original `clms` checkout in its dev container. Its retained PostgreSQL
volume and restored storage contain the original data. The rename commit is
recorded in `rename-revision` for a later retry; the checkout is detached at the
original revision. The full worktree archive also retains local secrets and
source inputs if they need recovery.

## Later cleanup

After acceptance, remove the stopped old app, Selenium, and PostgreSQL containers
and their obsolete app images when no longer needed. Remove
`solarhub_postgres_data` only after checking the backup and successful use of the
new environment. Keep a backup according to your normal retention policy.
Do not run `docker compose down --volumes` or volume-pruning commands during
the transition. Docker volumes have their own lifecycle; the explicit new
[volume name](https://docs.docker.com/reference/compose-file/volumes/#name)
keeps the new mount consistent between Compose and VS Code.
