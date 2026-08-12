# Phase 3 — Person C Context (Data Interaction + Dashboard UI)

This doc is a handoff brief for working on Person C's piece of a group cloud
project. Read this before touching code — it explains what already exists,
what's owned by teammates (don't rebuild or redeploy their pieces), and what's
actually left to build.

## The big picture

This is a 3-person Azure project. Each person's backend is a **separate,
independently deployed Azure Function App under their own subscription**.
There is no shared repo or shared codebase across people — integration
happens entirely through **live HTTPS URLs** that the dashboard's JavaScript
calls with `fetch()`, the same way you'd call any third-party API.

```
Your dashboard (static HTML/JS, deployed as an Azure Static Web App)
  │
  ├── fetch(PERSON_A_URL + '/api/analyze')     → Person A (precomputed summary stats)
  ├── fetch(YOUR_URL + '/api/recipes?...')     → YOU (search/filter/pagination — doesn't exist yet)
  ├── fetch(PERSON_B_URL + '/api/register')    → Person B (auth)
  ├── fetch(PERSON_B_URL + '/api/login')       → Person B (auth)
  ├── fetch(PERSON_B_URL + '/api/logout')      → Person B (auth)
  └── fetch(PERSON_B_URL + '/api/me')          → Person B (auth check on load)
```

**Team assignments (from the group's task split):**
- **Person A — Performance Core:** blob-trigger data cleaning, Redis/Cosmos caching
- **Person B — Auth & Security:** email/password + OAuth login, password hashing, encrypted DB
- **Person C (me) — Data Interaction + Dashboard UI:** search/filter/pagination API
  *using the cleaned data Person A produces*, login gate, logged-in user
  display + logout button, and final integration wiring A's and B's
  endpoints into the UI

## What already exists — Phase 2 codebase (starting point)

Uploaded as `cloud-proj-two.zip`. This is the team's **Phase 2** submission
(by Julia, Kaley, Enzo), built before the current Phase 3 person-split. Clone
this as the base to branch from — it already has a working dashboard shell.

Repo layout:
```
.
├── respin.ps1                  # provisions Azure + deploys both halves (Phase 2's own infra)
├── projtwo/                    # old backend — single /api/analyze endpoint, NOT the auth or search API
│   └── function_app.py
├── webapp/
│   └── index.html              # ← YOUR STARTING POINT. Chart.js dashboard, diet filter, refresh button
├── data/All_Diets.csv          # source dataset, ~7,800 recipes, 5 diet types
└── infra/arm-template.json     # portal export, NOT the deploy method — ignore for deploys
```

### `webapp/index.html` — what it already does
- Config row where a Function endpoint URL is pasted in, "Connect" button
- 4 Chart.js visualizations: grouped bar (avg macros), scatter (protein vs
  carbs), pie (diet distribution), horizontal bar (top cuisine per diet)
- A diet-type `<select>` filter — **but this only filters already-fetched
  JSON client-side**, it does not call a filtered API. This pattern needs to
  be replaced/extended with real server-side filtering for Phase 3.
- No login/auth of any kind. No user display. No logout button.
- Fetch pattern used throughout: plain `fetch(url)`, JSON response, try/catch
  around a `setStatus()` helper. Keep this style for new calls.

### CSV schema (from `data/All_Diets.csv`, confirmed in both old and new backend code)
Columns used: `Diet_type`, `Recipe_name`, `Cuisine_type`, `Protein(g)`,
`Carbs(g)`, `Fat(g)`. 5 diet types, ~7,800 rows.

## Person A — what's built and live (DO NOT rebuild or redeploy this)

**Live URL:** `https://diet-analysis-func-2026.azurewebsites.net`
**Region:** Canada Central. Storage account `dietanalysisst2026`. Redis: Basic tier.

Two functions in one Function App:

1. **`DietDataProcessor`** (blob trigger on `datasets/All_Diets.csv`)
   - Fires only when the raw CSV changes
   - Cleans data (fills numeric NaNs with column mean)
   - Saves the cleaned CSV to **`results/All_Diets_clean.csv`** ← **this is
     what your new search/filter/pagination endpoint should read from**
   - Computes and caches the full summary result in Redis under key
     `diet_analysis_results`

2. **`GET /api/analyze`**
   - Serves precomputed summary from Redis cache (fast path)
   - Falls back to reading raw blob + computing on cache miss only
   - Response includes `"source": "cache"` or `"source": "computed"`
   - **Response JSON shape** (same fields Phase 2's dashboard already expects,
     values below are illustrative, not fixed):
     ```json
     {
       "generated_at": "...",
       "total_recipes": 7800,
       "avg_macros_by_diet": [ { "Diet_type": "...", "Protein(g)": ..., "Carbs(g)": ..., "Fat(g)": ... }, ... ],
       "top_protein_recipes": [ { "Diet_type": "...", "Recipe_name": "...", "Protein(g)": ..., "Carbs(g)": ..., "Fat(g)": ... }, ... ],
       "most_common_cuisines": { "Diet_type": "Cuisine_type", ... },
       "diet_distribution": { "Diet_type": count, ... },
       "source": "cache" | "computed"
     }
     ```
   - Has `Access-Control-Allow-Origin: *`, so it's callable cross-origin with
     no extra config needed on your end.

**There is no search/filter/pagination endpoint from Person A.** That's
explicitly your responsibility, reading `results/All_Diets_clean.csv`
directly — not something to wait on a handoff for.

## Person B — what's built and live (DO NOT rebuild or redeploy this)

**Live URL:** `https://diet-analysis-auth-func-2026.azurewebsites.net`
**Repo (source, do not redeploy from it — integrate against the live URL):**
`https://github.com/Enzodabenzo123/cloudA3EKJ`

Data security: bcrypt-hashed passwords (never stored raw), Cosmos DB
(encrypted at rest by default, Azure-managed keys), stateless JWT sessions.

### Endpoints

**`POST /api/register`**
```json
// body
{ "email": "user@example.com", "password": "at least 8 chars", "name": "Jane Doe" }
// success 201
{ "token": "<JWT>", "name": "Jane Doe", "email": "user@example.com" }
// errors: 400 invalid email/password/name · 409 email already registered
```

**`POST /api/login`**
```json
// body
{ "email": "user@example.com", "password": "..." }
// success 200: same shape as register
// errors: 401 invalid email or password
```

**`POST /api/logout`**
No body. Returns `200 { "message": "Logged out" }`. JWTs are stateless — this
doesn't invalidate anything server-side. Real logout happens client-side:
delete the stored token and show the login screen. Call this endpoint first
as good practice, but it's not strictly required for logout to "work."

**`GET /api/me`**
Header: `Authorization: Bearer <token>`
```json
// success 200
{ "email": "user@example.com", "name": "Jane Doe" }
// error 401 if token missing/invalid/expired → treat as "not logged in", show login screen
```
Call this on dashboard load to (a) confirm the stored token is still valid
and (b) get the name for the top-right corner display.

**`GET /api/auth/github/login`**
Not a `fetch()` call — a link/redirect. Point a button at it directly:
```html
<button onclick="window.location.href = 'https://diet-analysis-auth-func-2026.azurewebsites.net/api/auth/github/login'">
  Login with GitHub
</button>
```
Flow: browser redirects to GitHub → user approves → GitHub redirects back
through Person B's callback → lands back on `YOUR_DASHBOARD_URL/#token=<JWT>`.

On page load your JS needs:
```js
const hash = window.location.hash;
if (hash.startsWith('#token=')) {
  const token = hash.substring('#token='.length);
  localStorage.setItem('authToken', token);
  window.location.hash = ''; // clean up the URL bar
}
```
From there, use the stored token as `Authorization: Bearer <token>` on
`/api/me` and any other authenticated calls, for both login paths.

### Outstanding action item — you owe Person B something
**Send Person B your dashboard's URL** (local dev URL now, real deployed URL
later) so they can set it as their Function App's `FRONTEND_URL` setting —
otherwise the GitHub OAuth redirect lands on a placeholder and breaks.

## What's actually left to build (your real Phase 3 work)

1. **New Azure Function endpoint** (e.g. `GET /api/recipes`), your own
   Function App, own deployment:
   - Reads `results/All_Diets_clean.csv` from Person A's `results` blob container
   - Query params: diet-type filter, keyword search (recipe name / cuisine),
     pagination (e.g. `page`, `page_size`)
   - Returns paginated JSON list of matching recipes
   - `Access-Control-Allow-Origin: *` like the others
   - Rubric-relevant: diet filter (5 pts), keyword search (10 pts), pagination (5 pts)

2. **Login gate in `webapp/index.html`:**
   - On page load, check `localStorage` for a token; if present call
     `GET /api/me` to validate
   - If no valid token → show a login/register form (email+password fields +
     "Login with GitHub" button), hide the dashboard `<main>`
   - On successful login/register → store token, show dashboard
   - Handle the `#token=` hash fragment from the GitHub OAuth redirect (code above)

3. **Top-right user display + logout:**
   - Show the logged-in user's `name` (from `/api/me`) in the header
   - Logout button: call `POST /api/logout` (optional but good practice),
     delete stored token, show login screen again
   - Rubric-relevant: dashboard UI gate + name display (10 pts)

4. **Wire in the new recipe search UI** alongside the existing charts —
   a searchable/filterable/paginated recipe list, calling your new endpoint.

5. **Deploy your new Function App under your own Azure subscription**,
   mirroring Person A/B's pattern (your own `respin.ps1` or manual deploy).
   No shared repo needed with A or B.

## Gotchas / things not to do

- **Don't redeploy Person A's or Person B's Function Apps.** Their code repos
  exist for reference/integration, not for you to run their deploy scripts.
- **Never run someone else's `respin.ps1`** unless their live instance is
  actually lost. Person B's explicitly warns: it recreates infra under a new
  name but does *not* touch Cosmos DB, and needs manual follow-up (app
  settings, OAuth callback URL update, telling the team if the URL changed).
  Running it casually can break the live URL everyone else is integrating against.
- **Your own team's `respin.ps1`** (Phase 2 repo) deletes and recreates the
  whole resource group each session to save cost — be aware it can wipe
  state you're mid-testing with.
- **`local.settings.json` is gitignored on purpose** (holds connection
  strings) — don't force-add it.
- Match the existing JSON response shape / fetch style already used in
  `webapp/index.html` and Person A's `analyze` endpoint so nothing needs
  reworking on the frontend side later.
