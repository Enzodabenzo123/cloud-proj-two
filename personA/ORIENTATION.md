# Orientation — working in one VS Code project

You now have three previously-separate pieces. This doc explains how they
relate, what folder structure to put them in, what's actually live right
now, and the exact order of operations left to finish.

## Suggested folder structure

Put everything under one root and open that root in VS Code:

```
diet-dashboard-personc/
├── webapp/
│   └── index.html                    ← your dashboard (Claude Code already
│                                        added login gate, OAuth handling,
│                                        user display/logout, search UI)
├── recipes-api/                      ← YOUR new Function App
│   ├── function_app.py
│   ├── requirements.txt
│   ├── host.json
│   ├── local.settings.json.example
│   ├── deploy-recipes-api.ps1
│   └── README.md
├── person-a-rebuild/                 ← rebuilt copy of Person A's pipeline,
│   ├── function_app.py                 kept in ITS OWN resource group,
│   ├── requirements.txt                deliberately separate from recipes-api
│   ├── host.json
│   ├── rebuild-person-a-stack.ps1
│   └── DISCLOSURE_NOTE.md
├── PHASE3_PERSON_C_CONTEXT.md         ← original handoff reference doc
└── ORIENTATION.md                     ← this file
```

`webapp/` came from your Phase 2 repo. `recipes-api/` and `person-a-rebuild/`
are new, built in this conversation. They're kept as separate folders
because they deploy to **separate Azure resource groups** — that separation
matters, don't merge the code together even though they'll end up talking to
each other over HTTPS.

## What's actually live right now

| Piece | Status |
|---|---|
| Dashboard (`webapp/index.html`) | **Live** — deployed as an Azure Static Web App at `salmon-pebble-0ae7ba210.7.azurestaticapps.net`, own resource group `diet-dashboard-personc-rg` |
| Person B's auth API | **Live** — has your real dashboard URL, OAuth fully wired end-to-end |
| Person A's *original* pipeline | **Down** — resource group was deleted between sessions to save cost. Already fully built and demoed on video before deletion. |
| `person-a-rebuild/` stack | **Not deployed yet** — script is written, hasn't been run |
| `recipes-api/` (your search/filter/pagination API) | **Not deployed yet** — code is written, blocked on having a working storage connection string |

The dashboard's login flow and charts (against Person A's `/api/analyze`)
worked end-to-end *before* the original resource went down. Once you run
`person-a-rebuild/`, you'll need to point the dashboard at the *new*
`/api/analyze` URL, since the old one no longer resolves.

## Order of operations to finish

1. **Run the Person A rebuild:**
   ```powershell
   cd person-a-rebuild
   ./rebuild-person-a-stack.ps1 -DietCsvPath "..\webapp\..\data\All_Diets.csv"
   ```
   (adjust the CSV path to wherever your copy of `All_Diets.csv` actually
   lives). This takes ~15-20 min mostly waiting on Redis to provision.
   At the end it prints two things you need:
   - A working `/api/analyze` URL
   - A storage connection string

2. **Update the dashboard's Person A endpoint config** in `webapp/index.html`
   to the new `/api/analyze` URL from step 1 — the old
   `diet-analysis-func-2026` URL is dead and needs replacing.

3. **Deploy your recipes API**, using the connection string from step 1:
   ```powershell
   cd ../recipes-api
   ./deploy-recipes-api.ps1 -PersonAConnectionString "<connection string from step 1>"
   ```
   Prints your live `/api/recipes` and `/api/diet-types` URLs.

4. **Paste that recipes API URL** into the dashboard's recipe search config
   field — the search UI is already built and wired, it's just been waiting
   for a real endpoint.

5. **Redeploy/refresh the dashboard** so the updated config (steps 2 and 4)
   goes live on the Static Web App.

6. **Smoke-test everything live**, in this order: register/login → GitHub
   OAuth → charts load from `/api/analyze` → search recipes by keyword and
   diet type → paginate → logout.

7. **Record the video.** Include the disclosure note (see
   `person-a-rebuild/DISCLOSURE_NOTE.md`) briefly during the
   performance-optimization section, since you're the one demoing a
   redeployed copy of that pipeline, not the original.

## Things to keep in mind while working in VS Code

- **Never commit real connection strings or keys.** `local.settings.json` in
  `recipes-api/` (and any equivalent in `person-a-rebuild/`) should be
  gitignored — only the `.example` template gets committed.
- **`recipes-api/` and `person-a-rebuild/` are two different Azure
  subscriptions' worth of resources, but both under your account.** Keep
  their resource group names distinct (`diet-dashboard-personc-rg` vs
  `diet-analysis-rebuild-personc-rg`) so you can tell them apart in the
  portal and tear down independently.
- **`webapp/` still has `respin.ps1`** from the original Phase 2 team repo —
  that's a different script for a different resource group (the shared
  team one, if you're still using it) and is unrelated to the two new
  scripts above.
- Cost hygiene: once you're done recording, the priciest resource left
  running is Redis in `person-a-rebuild/` — Basic tier bills continuously.
  Delete or downsize that resource group after your submission is in.
