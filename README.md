# Diet Analysis Cloud Dashboard — Project Phase 2

A serverless cloud dashboard that analyses a recipe/diet dataset. An Azure
Function reads the dataset from Azure Blob Storage, cleans it, computes
per-diet nutritional statistics, and returns JSON. A static web dashboard
fetches that JSON and renders it as interactive charts.

## Architecture

```
                    +---------------------------+
  Browser  ───────► |  Azure Static Web App     |   (dashboard: index.html)
                    |  diet-dashboard-swa-e     |
                    +------------+--------------+
                                 │ fetch() GET /api/analyze
                                 ▼
                    +---------------------------+
                    |  Azure Function (Python)  |   HTTP trigger, anonymous
                    |  diet-analysis-func-2026e |
                    +------------+--------------+
                                 │ reads blob
                                 ▼
                    +---------------------------+
                    |  Azure Blob Storage       |   container: datasets
                    |  dietanalysisst2026e      |   blob: All_Diets.csv
                    +---------------------------+
```

All resources live in the resource group **diet-analysis-rg** (Central US).

## Repository structure

```
.
├── respin.ps1                    # One-shot: provisions Azure + deploys both halves
├── README.md
├── .gitignore
├── projtwo/                      # Backend (Azure Function)
│   ├── function_app.py           # analyze endpoint: reads CSV, computes stats, returns JSON
│   ├── host.json
│   ├── requirements.txt
│   ├── .funcignore
│   └── local.settings.json.example
├── webapp/                       # Frontend (static dashboard)
│   └── index.html                # Chart.js dashboard, 4 visualizations + filter + refresh
├── data/
│   └── All_Diets.csv             # Source dataset (~7,800 recipes, 5 diet types)
└── infra/
    └── arm-template.json         # Reference: portal export of the backend (NOT the deploy method)
```

## What the function returns

`GET /api/analyze` responds with JSON containing:

- `execution_time_seconds` — server-side processing time (dashboard metadata)
- `total_recipes` — row count after cleaning
- `avg_macros_by_diet` — mean protein/carbs/fat per diet type
- `top_protein_recipes` — top 5 highest-protein recipes per diet type
- `most_common_cuisines` — dominant cuisine per diet type
- `diet_distribution` — recipe count per diet type

The dashboard renders these as a grouped bar chart, a protein-vs-carbs scatter,
a distribution pie, and a per-diet cuisine chart, plus a diet-type filter and a
refresh button.

## Deploying (respin)

The resource group is deleted between sessions to save cost. To bring the whole
stack back up, run the respin script from the repo root.

**One-time prerequisites:**

```powershell
az login
npm install -g azure-functions-core-tools@4
npm install -g @azure/static-web-apps-cli
```

**Then:**

```powershell
cd <repo root>
.\respin.ps1
```

The script provisions the resource group, storage account, dataset container,
uploads the CSV, creates and deploys the Function App, sets the storage
connection string as an app setting, then creates the Static Web App and
deploys the dashboard. It prints both live URLs at the end.

Paths are resolved relative to the script's own location, so the repo can be
cloned anywhere. The two globally-unique names (`$STORAGE`, `$FUNCTIONAPP`) are
set at the top of the script — bump the suffix letter if a name is ever taken.

## Using the dashboard

1. Open the Static Web App URL printed by respin.
2. Paste the Function URL (`https://diet-analysis-func-2026e.azurewebsites.net/api/analyze`)
   into the endpoint field.
3. Click **Connect**. Use the diet-type filter and **Refresh** to interact.

## Notes on cloud practices

- The storage connection string is injected as an Azure **app setting**, never
  committed. `local.settings.json` is git-ignored; a `.example` template is
  provided for local runs.
- The Function uses an anonymous HTTP trigger for coursework simplicity and
  returns an `Access-Control-Allow-Origin` header so the browser dashboard can
  call it cross-origin without extra CORS configuration.
- `infra/arm-template.json` is a portal export kept for documentation of the
  deployed backend. It is **not** run to deploy; `respin.ps1` is the deployment
  method.

## Team

- Julia — Backend / Azure:** Function app, blob storage, connection-string
  configuration, endpoint testing.
- Kaley — Frontend / Dashboard:** Dashboard UI, charts, filter/refresh
  controls, Static Web App deployment, respin script.
- Enzo -  Integration / Documentation:** Altered respin script, End-to-end integration, GitHub
  repository, documentation PDF.
