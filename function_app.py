import azure.functions as func
import logging
import json
import io
import math
import os
import pandas as pd
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

# Person A's storage account holds the cleaned CSV — this connection string
# (or SAS-scoped connection string) comes from them, not from your own
# subscription. See README for how to get it.
PERSON_A_CONNECTION_STRING = os.environ["PERSON_A_STORAGE_CONNECTION_STRING"]
RESULTS_CONTAINER = "results"
CLEAN_BLOB_NAME = "All_Diets_clean.csv"

CORS_HEADERS = {"Access-Control-Allow-Origin": "*"}

# Cached per warm instance so repeated requests don't re-download the CSV
# every time. Cleared automatically whenever the instance recycles.
_cached_df = None


def load_clean_data() -> pd.DataFrame:
    global _cached_df
    # * DEMO: reads Person A's already-cleaned CSV — no re-cleaning happens here
    if _cached_df is not None:
        return _cached_df

    blob_service_client = BlobServiceClient.from_connection_string(PERSON_A_CONNECTION_STRING)
    container_client = blob_service_client.get_container_client(RESULTS_CONTAINER)
    blob_client = container_client.get_blob_client(CLEAN_BLOB_NAME)
    stream = blob_client.download_blob().readall()
    _cached_df = pd.read_csv(io.BytesIO(stream))
    return _cached_df


@app.route(route="recipes", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def recipes(req: func.HttpRequest) -> func.HttpResponse:
    """
    GET /api/recipes?diet_type=paleo&keyword=chicken&page=1&page_size=20
    All query params are optional. diet_type and keyword are case-insensitive.
    """
    logging.info("recipes endpoint called")

    try:
        df = load_clean_data()

        diet_type = req.params.get("diet_type")
        keyword = req.params.get("keyword")

        try:
            page = int(req.params.get("page", 1))
        except ValueError:
            page = 1
        try:
            page_size = int(req.params.get("page_size", 20))
        except ValueError:
            page_size = 20

        page = max(page, 1)
        page_size = min(max(page_size, 1), 100)

        filtered = df

        # ? DEMO: diet-type filter — case-insensitive exact match
        if diet_type:
            filtered = filtered[filtered["Diet_type"].str.lower() == diet_type.lower()]

        # ? DEMO: keyword search across recipe name and cuisine type
        if keyword:
            kw = keyword.lower()
            mask = (
                filtered["Recipe_name"].str.lower().str.contains(kw, na=False)
                | filtered["Cuisine_type"].str.lower().str.contains(kw, na=False)
            )
            filtered = filtered[mask]

        # ? DEMO: pagination math — total_pages + slice by page/page_size
        total_results = len(filtered)
        total_pages = max(1, math.ceil(total_results / page_size))
        start = (page - 1) * page_size
        end = start + page_size
        page_df = filtered.iloc[start:end]

        result = {
            "page": page,
            "page_size": page_size,
            "total_results": total_results,
            "total_pages": total_pages,
            "diet_type": diet_type,
            "keyword": keyword,
            "recipes": page_df[
                ["Diet_type", "Recipe_name", "Cuisine_type", "Protein(g)", "Carbs(g)", "Fat(g)"]
            ].to_dict(orient="records"),
        }

        return func.HttpResponse(
            json.dumps(result),
            mimetype="application/json",
            status_code=200,
            headers=CORS_HEADERS,
        )

    except Exception as e:
        logging.error(f"Error in recipes endpoint: {e}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            mimetype="application/json",
            status_code=500,
            headers=CORS_HEADERS,
        )


@app.route(route="diet-types", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def diet_types(req: func.HttpRequest) -> func.HttpResponse:
    """
    GET /api/diet-types
    Convenience endpoint so the dashboard can populate the filter dropdown
    from real data instead of a hardcoded list.
    """
    try:
        df = load_clean_data()
        types = sorted(df["Diet_type"].dropna().unique().tolist())
        return func.HttpResponse(
            json.dumps({"diet_types": types}),
            mimetype="application/json",
            status_code=200,
            headers=CORS_HEADERS,
        )
    except Exception as e:
        logging.error(f"Error in diet-types endpoint: {e}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            mimetype="application/json",
            status_code=500,
            headers=CORS_HEADERS,
        )
