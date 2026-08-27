# Operational contract

Status: frozen for Regulatory Data Core v1 by roadmap PR1.

This is the canonical operating contract for local topology, secrets, migrations, legacy
coexistence, cutover, and recovery. `docs/two-laptop-workflow.md` is the practical day-to-day guide.

## Local topology

Laptop A and Laptop B each have:

- an independent Git clone outside OneDrive, Dropbox, Google Drive, or any automatic sync folder;
- a local `.venv` reproduced from the version-controlled project and lockfile;
- a local, untracked `.env` populated separately;
- no copied `.git`, `.venv`, or source tree from the other laptop.

GitHub is the only synchronization mechanism for code, branches, and migrations. Uncommitted work
is not transferred between laptops.

Supabase is the shared remote backend. It shares application data and deployed database state; it
does not synchronize source code. Schema changes reach it only through versioned Git migrations.

## Secrets topology

Only names and roles are documented. Never print, inspect, validate, or record real values in docs,
logs, tests, screenshots, or review output.

| Name | Role | Allowed locations |
|---|---|---|
| `MBM_DATABASE_URL` | Server-side PostgreSQL connection | Each laptop's `.env`; protected GitHub Environment secret for jobs that need DB access |
| `MBM_SUPABASE_URL` | Supabase project API URL | Local `.env`; protected job configuration; client only where required |
| `MBM_SUPABASE_SECRET_KEY` | Server-side ingestion/administration credential | Local `.env` when needed; protected GitHub Environment secret; never browser code |
| `MBM_SUPABASE_PUBLISHABLE_KEY` | Public/publishable client credential | Local `.env` and dashboard/client configuration after read-only RLS is verified |

The existing migration workflow also refers to protected Supabase CLI deployment credentials.
Their values, project reference, database password, and access tokens remain outside Git. A
publishable key is not a substitute for server authorization; a secret key is never public.

## Migration contract

- All migrations are forward-only.
- Never edit a migration after it has been merged or applied anywhere shared.
- Treat the remote database as potentially applied and containing valuable data.
- Never run automatic repair, reset, history rewrite, or destructive rollback against remote.
- Complete a read-only remote inventory before the first v1 schema PR is created or deployed.
- Permit one schema PR in flight at a time.
- Complete `merge → deploy → verify` before starting the next schema PR.
- Do not make ad-hoc production schema changes; every production change must exist in Git.
- Freeze legacy schemas `core`, `ops`, and `analytics`; do not reinterpret their objects in place.
- Do not dual-write between legacy and v1.
- Create v1 in new schemas separated by responsibility.

Planned v1 schemas are:

- `evidence` — regulators, sources, releases, and artifacts;
- `registry` — institutions, registrations, aliases, controlled scopes, units, and source concepts;
- `reported` — reported facts and supersession chains;
- `semantic` — canonical concepts, mapping versions, and reproducible canonical views;
- `metrics` — definition versions, calculation runs, observations, and inputs;
- `audit` — ingestion runs, quality issues, and append-only review decisions;
- `serving` — observed/publishable current and as-of query surfaces;
- `public` — explicitly versioned public contracts.

Their physical creation belongs to later PRs. PR1 creates no schema or migration.

## Production migration deployment safety

Production migration deployment is manual, runs only from `main`, and is serialized. Before the
only schema-mutating command, the workflow validates the local migration repository, compares the
linked remote history, rejects destructive SQL in the pending suffix, and verifies the official
Supabase dry-run plan. History and dry-run gates consume only the CLI's official structured JSON
stdout; malformed or schema-incompatible payloads fail closed. A remote history with no trusted
common baseline is not treated as a fresh database automatically; it requires separate inventory
and reconciliation.

Failure handling is fail-closed and forward-only:

- History drift before push stops the workflow without mutation. It never repairs or rewrites the
  remote history.
- A failed or inconsistent dry-run stops the workflow without mutation.
- Destructive DDL in a pending migration stops the workflow without mutation. PR6 defines no
  exception or allowlist.
- A failed or partially applied `db push` fails the workflow. Preserve the logs and remote state for
  investigation; do not roll back, reset, or repair automatically.
- Failed post-push history or no-op verification fails the workflow and preserves evidence for
  investigation. It never attempts automatic reconciliation.

The workflow verifies deployment state, not business-schema equivalence. The pending read-only
remote inventory remains mandatory before the first v1 schema PR.

## Legacy coexistence and cutover

- Do not change legacy primary keys for convenience.
- Keep legacy objects available throughout v1 implementation and consumer cutover.
- Future v1 writers write only to v1 schemas.
- Run and reconcile the v1 vertical slice without changing existing consumers.
- Migrate each reader/consumer explicitly to a versioned v1 contract.
- Add a compatibility view only when semantic equivalence is demonstrated, tested, and documented.
- Do not present `public.bank_metrics` as the v1 contract; the planned contract is separately
  versioned.
- Retire legacy only in a future, separate PR after zero consumers and reconciliation are proven.

## Recovery and rollback

Recovery is operational and forward-only:

1. Stop or disable the affected v1 writer or reader.
2. Return a consumer temporarily to the legacy contract when viable.
3. Preserve v1 schema and data for diagnosis.
4. Correct the fault with a new migration and/or commit.
5. Deploy, verify, and document any required reconciliation.

Never:

- delete production data/schema to “roll back”;
- edit or automatically repair migration history;
- run `db reset` against remote;
- remove evidence or facts to conceal an incorrect load.

## Two-laptop schema workflow

The laptop performing a schema PR must complete this sequence:

```text
sync main
→ create the requested branch
→ apply/test on a local or disposable test database
→ run appropriate tests and .\scripts\check.ps1
→ open and review the PR
→ merge to main
→ deploy the merged migration to remote
→ verify migration history, schema, and intended behavior
```

Only after remote verification may the other laptop:

```text
update main
→ synchronize the merged migrations into its independent clone/local database
→ begin subsequent work
```

Do not develop concurrent schema branches or continue from stale migration history.

## Gate before v1 schema work

The pending remote inventory is read-only and must establish migration history, existing objects,
legacy dependencies/consumers, and relevant row counts without exposing secrets. Unexpected drift
stops schema work; it is reported and resolved deliberately, never repaired automatically.
