# Diet Analysis — Auth Service (Person B)

Email/password + GitHub OAuth authentication backend for the Diet Analysis dashboard, Phase 3. Python Azure Function App, user data in Cosmos DB.

**Live URL:** `https://diet-analysis-auth-func-2026.azurewebsites.net`

This is the source code for that live deployment — Person C and anyone reviewing the project should integrate against the live URL directly (see `AUTH_API_REFERENCE.md`), **not** redeploy a separate copy of this. A second independent deployment would mean a second, disconnected user database — accounts registered on one wouldn't exist on the other.

## What's here

- `function_app.py` — the five endpoints: register, login, logout, me, and the GitHub OAuth pair
- `AUTH_API_REFERENCE.md` — request/response formats for integrating this into the dashboard
- `respin.ps1` — redeploys the compute layer (storage account + Function App) only, for disaster recovery. **Does not touch Cosmos DB** — that's where real user accounts live, and recreating it would wipe them
- `local.settings.json.example` — the environment variables this needs, with placeholder values

## Local setup

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy local.settings.json.example local.settings.json
# fill in local.settings.json with real values (never commit this file)
func start
```

## Redeploying (only if the live instance is ever lost)

```powershell
./respin.ps1
```

This creates a fresh storage account + Function App under a new name and publishes the current code to it. It intentionally does not recreate Cosmos DB. After it runs, you still need to manually set application settings, update the GitHub OAuth App's callback URL, and let the team know if the base URL changed. Full steps print at the end of the script.

## Data & security notes

- Passwords are bcrypt-hashed; the raw password is never stored.
- Cosmos DB encrypts data at rest by default (Azure-managed keys, no extra config).
- Sessions are stateless JWTs, signed with `JWT_SECRET`. Logout is client-side (delete the stored token).
