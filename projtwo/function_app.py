import azure.functions as func
import logging
import json
import io
import os
from datetime import datetime
import pandas as pd
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

STORAGE_CONNECTION_STRING = os.environ["STORAGE_CONNECTION_STRING"]
CONTAINER_NAME = "datasets"
BLOB_NAME = "All_Diets.csv"

@app.route(route="analyze", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def analyze(req: func.HttpRequest) -> func.HttpResponse:
    start_time = datetime.now()
    logging.info("Diet analysis function triggered.")

    try:
        # Connect to Azure Blob Storage
        blob_service_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        blob_client = container_client.get_blob_client(BLOB_NAME)

        # Download and read CSV
        stream = blob_client.download_blob().readall()
        df = pd.read_csv(io.BytesIO(stream))

        # Data cleaning
        numeric_columns = ["Protein(g)", "Carbs(g)", "Fat(g)"]
        for col in numeric_columns:
            df[col] = df[col].fillna(df[col].mean())

        # Analysis
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

        execution_time = (datetime.now() - start_time).total_seconds()

        result = {
            "execution_time_seconds": execution_time,
            "total_recipes": len(df),
            "avg_macros_by_diet": avg_macros.reset_index().to_dict(orient="records"),
            "top_protein_recipes": top_protein[["Diet_type", "Recipe_name", "Protein(g)", "Carbs(g)", "Fat(g)"]].to_dict(orient="records"),
            "most_common_cuisines": most_common_cuisines,
            "diet_distribution": diet_counts,
        }

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
