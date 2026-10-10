#!/bin/sh
# Checks the SQL of the sync on a plain Postgres (version 15 or newer). It
# makes a new database, puts a small stand-in for Supabase in it, runs the
# migration files two times, runs the checks, runs the migration files one
# more time and checks that nothing was lost.
#
# It talks to the Postgres of this computer only (the usual PG* variables
# say where). Never run it on a Supabase project.
#
#   ./supabase/tests/run.sh [name of the test database]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
db=${1:-grove_sql_test}

run() {
  psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$1"
}

migrate() {
  for file in "$here"/../migrations/*.sql; do
    run "$file"
  done
}

dropdb --if-exists "$db"
createdb "$db"
run "$here/stub_supabase.sql"
echo "The migration, first time"
migrate
echo "The migration, second time"
migrate
echo "The checks"
run "$here/sync_test.sql"
echo "The migration, on a database with rows"
migrate
run "$here/after_rerun_test.sql"
dropdb "$db"
echo "All SQL checks passed."
