# Person C — recipes search/filter/pagination API

This is the piece from `PHASE3_PERSON_C_CONTEXT.md`, item 1: a new Azure
Function that reads Person A's cleaned CSV and serves search, filter, and
pagination to your dashboard.

## Files

| File | Purpose |
|---|---|
| `function_app.py` | The two endpoints: `/api/recipes` (search/filter/pagination) and `/api/diet-types` (for populating the filter dropdown) |
| `requirements.txt` | Python dependencies |
| `host.json` | Standard Functions runtime config |
| `local.settings.json.example` | Copy to `local.settings.json` for local testing — never commit the real one |
| `deploy-recipes-api.ps1` | Provisions the Azure infra and deploys this code, in one run |

## One thing you need before running the script

**A connection string that can read Person A's `results` container.** Their
storage account is under their own subscription, so you can't use your own
credentials to reach it. Ask Person A for one of these (in order of
preference):

1. **Best — a container-scoped SAS token**, read-only, on just the `results`
   container. They generate it with something like:
   ```
   az storage container generate-sas \
     --account-name dietanalysisst2026 \
     --name results \
     --permissions r \
     --expiry 2026-12-31 \
     --output tsv
   ```
   Then build the connection-string-style value for your app setting, or use
   the blob SDK's `BlobServiceClient(account_url, credential=sas_token)`
   pattern instead of `from_connection_string` if they hand you a bare SAS.
2. **Simpler but broader — their full storage account connection string.**
   Works fine for a class project, just means you technically have write
   access to their whole account too. Fine to use if you trust the
   handoff and want to move fast.

Whichever you get, that's the value for `PERSON_A_STORAGE_CONNECTION_STRING`.

## Running it

```powershell
./deploy-recipes-api.ps1 -PersonAConnectionString "<the connection string from Person A>"
```

That single command:
1. Logs you into Azure if you aren't already
2. Creates a resource group, a storage account (for the Functions runtime
   itself — not the data), and a Python Function App on a Consumption plan
3. Sets the connection string as an app setting
4. Turns on CORS for all origins, same as Person A and B's setup
5. Publishes `function_app.py` to it
6. Prints your live API URL and two example requests to try

Optional parameters if you want control over naming/region:
```powershell
./deploy-recipes-api.ps1 `
  -PersonAConnectionString "<...>" `
  -ResourceGroup "my-custom-rg" `
  -Location "canadacentral" `
  -FunctionAppName "my-recipes-api-2026"
```

## Tearing it down between sessions

Same idea as the team's `respin.ps1` — delete the resource group when you're
not actively working, to save cost:
```powershell
./deploy-recipes-api.ps1 -PersonAConnectionString "x" -Teardown
```
Note: if you don't pin `-FunctionAppName`, re-running the script afterward
generates a new random name and therefore a new URL. If that happens, update
your dashboard's config and let Person B know if you'd already sent them a
URL for `FRONTEND_URL`.

## Testing locally before deploying

```bash
python -m venv .venv
source .venv/bin/activate   # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
cp local.settings.json.example local.settings.json
# edit local.settings.json with your real PERSON_A_STORAGE_CONNECTION_STRING
func start
```
Then hit `http://localhost:7071/api/recipes?diet_type=paleo&page=1`.

## After it's deployed

Point your dashboard's fetch calls at the printed URL, e.g.:
```js
fetch(`${YOUR_RECIPES_API_URL}/api/recipes?diet_type=${diet}&keyword=${q}&page=${page}`)
```

This does **not** replace sending Person B your dashboard's URL — that's a
separate, still-outstanding item from the context doc.
