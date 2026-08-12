import azure.functions as func
import logging
import json
import io
import os
from datetime import datetime
import pandas as pd
import redis
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

STORAGE_CONNECTION_STRING = os.environ["STORAGE_CONNECTION_STRING"]
REDIS_HOST = os.environ["REDIS_HOST"]
REDIS_KEY = os.environ["REDIS_KEY"]

CONTAINER_NAME = "datasets"
BLOB_NAME = "All_Diets.csv"
RESULTS_CONTAINER = "results"
CLEAN_BLOB_NAME = "All_Diets_clean.csv"
CACHE_KEY = "diet_analysis_results"

redis_client = redis.Redis(
    host=REDIS_HOST,
    port=6380,
    password=REDIS_KEY,
    ssl=True,
    decode_responses=True
)


def run_analysis(df: pd.DataFrame) -> dict:
    """Cleans the dataframe and computes all analysis results."""
    numeric_columns = ["Protein(g)", "Carbs(g)", "Fat(g)"]
    for col in numeric_columns:
        df[col] = df[col].fillna(df[col].mean())

    avg_macros = df.groupby("Diet_type")[["Protein(g)", "Carbs(g)", "Fat(g)"]].mean()

    top_protein = (
        df.sort_values("Protein(g)", ascending=False)
        .groupby("Diet_type")
        .head(5)
    )

    most_common_cuisines = df.groupby("Diet_type")["Cuisine_type"].agg(
        lambda x: x.mode()[0] if len(x.mode()) > 0 else "N/A"
    ).to_dict()

    diet_counts = df["Diet_type"].value_counts().to_dict()

    result = {
        "generated_at": datetime.now().isoformat(),
        "total_recipes": len(df),
        "avg_macros_by_diet": avg_macros.reset_index().to_dict(orient="records"),
        "top_protein_recipes": top_protein[["Diet_type", "Recipe_name", "Protein(g)", "Carbs(g)", "Fat(g)"]].to_dict(orient="records"),
        "most_common_cuisines": most_common_cuisines,
        "diet_distribution": diet_counts,
    }
    return result, df


@app.blob_trigger(arg_name="myblob", path=f"{CONTAINER_NAME}/{BLOB_NAME}",
                   connection="STORAGE_CONNECTION_STRING")
def DietDataProcessor(myblob: func.InputStream):
    logging.info(f"Blob trigger fired for: {myblob.name}, size: {myblob.length} bytes")

    try:
        stream = myblob.read()
        df = pd.read_csv(io.BytesIO(stream))

        result, cleaned_df = run_analysis(df)

        # Save cleaned CSV so Person C's search/filter API can use it
        blob_service_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
        results_container = blob_service_client.get_container_client(RESULTS_CONTAINER)
        clean_csv_bytes = cleaned_df.to_csv(index=False).encode("utf-8")
        results_container.upload_blob(name=CLEAN_BLOB_NAME, data=clean_csv_bytes, overwrite=True)
        logging.info(f"Saved cleaned CSV to {RESULTS_CONTAINER}/{CLEAN_BLOB_NAME}")

        # Cache the computed results
        redis_client.set(CACHE_KEY, json.dumps(result))
        logging.info(f"Cached analysis results under key '{CACHE_KEY}'")

    except Exception as e:
        logging.error(f"Error processing blob: {e}")


@app.route(route="analyze", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def analyze(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Analyze endpoint called - reading from cache.")

    try:
        cached = redis_client.get(CACHE_KEY)

        if cached:
            result = json.loads(cached)
            result["source"] = "cache"
            return func.HttpResponse(
                json.dumps(result),
                mimetype="application/json",
                status_code=200,
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # Cache miss (e.g. first run before any blob trigger fired) - compute once
        logging.warning("Cache miss - computing on demand.")
        blob_service_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        blob_client = container_client.get_blob_client(BLOB_NAME)
        stream = blob_client.download_blob().readall()
        df = pd.read_csv(io.BytesIO(stream))

        result, _ = run_analysis(df)
        redis_client.set(CACHE_KEY, json.dumps(result))
        result["source"] = "computed"

        return func.HttpResponse(
            json.dumps(result),
            mimetype="application/json",
            status_code=200,
            headers={"Access-Control-Allow-Origin": "*"}
        )

    except Exception as e:
        logging.error(f"Error: {e}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            mimetype="application/json",
            status_code=500
        )
