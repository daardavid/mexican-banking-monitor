# Working safely from two laptops

## One-time setup on each Windows laptop

1. Install Git, GitHub CLI, and uv:

   ```powershell
   winget install --id Git.Git -e
   winget install --id GitHub.cli -e
   winget install --id astral-sh.uv -e
   ```

2. Authenticate that laptop directly with GitHub:

   ```powershell
   gh auth login
   ```

3. Clone the repository into a normal local development folder. Do not place the working repository
   inside OneDrive, Dropbox, or another folder-sync product.

4. Run:

   ```powershell
   .\scripts\bootstrap.ps1
   ```

5. Populate `.env` locally. Never send `.env` through chat, email, or Git.

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

Avoid editing the same uncommitted branch on both laptops. Git transfers code and migrations;
Supabase transfers shared application data; neither replaces the other.

## Schema changes

- Create a new SQL migration; never edit a migration already applied remotely.
- Test the change and open a pull request.
- Merge it to `main`.
- Run the manual `Deploy database migrations` workflow.
- Confirm migration history before beginning another schema change.
