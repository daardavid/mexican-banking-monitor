# Working safely from two laptops

This is the practical workflow. The canonical rules for topology, secrets, migrations, cutover, and
recovery are frozen in [the operational contract](operations/operational-contract.md). If this guide
and that contract ever differ, stop and correct the documentation before continuing.

## One-time setup on each Windows laptop

1. Install Git, GitHub CLI, and uv:

   ```powershell
   winget install --id Git.Git -e
   winget install --id GitHub.cli -e
   winget install --id astral-sh.uv -e --version 0.12.6
   ```

2. Authenticate that laptop directly with GitHub:

   ```powershell
   gh auth login
   ```

3. Clone the repository independently into a normal local development folder. Do not place the
   working repository inside OneDrive, Dropbox, Google Drive, or another folder-sync product. Do not
   copy `.git`, `.venv`, or the source tree from the other laptop.

4. Run:

   ```powershell
   .\scripts\bootstrap.ps1
   ```

5. Populate `.env` locally. Each laptop keeps its own `.env` and `.venv`; never send either through
   chat, email, Git, or a folder-sync product.

## Daily workflow

Before starting on either laptop:

```powershell
git switch main
git pull --ff-only
git switch -c feature/short-description
```

Before moving to the other laptop:

```powershell
.\scripts\check.ps1
git add -A
git commit -m "Describe the completed change"
git push -u origin HEAD
```

On the other laptop, fetch the same branch instead of recreating files manually:

```powershell
git fetch --prune
git switch feature/short-description
git pull --ff-only
```

Avoid editing the same uncommitted branch on both laptops. GitHub is the only synchronization path
for code, branches, and migrations. Supabase is the shared backend for deployed schema and
application data; it does not transfer code.

## Schema changes

- Complete the required read-only remote inventory before the first v1 schema PR.
- Allow only one schema PR in flight.
- Create a new forward-only SQL migration; never edit one already merged or applied.
- Test against a local or disposable test database and run `.\scripts\check.ps1`.
- Open the PR, review it, and merge it to `main`.
- Deploy the merged migration through the controlled migration workflow.
- Verify remote migration history and intended behavior.
- Only then may the other laptop update `main`, synchronize migrations, and continue.

Never reset or automatically repair the shared remote database. Never dual-write between legacy and
v1. Recovery disables the affected v1 path, preserves its data for diagnosis, and fixes forward with
a new migration or commit; see the operational contract for the full procedure.
