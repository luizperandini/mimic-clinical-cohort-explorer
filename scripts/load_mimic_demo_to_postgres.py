import os
import pandas as pd
from sqlalchemy import create_engine, URL

ROOT = r"c:\Users\lpera\Dropbox\Dados e IA\MIMIC_Project"

DB_USER = "postgres"
DB_PASSWORD = "Paty2829@#.,"
DB_HOST = "localhost"
DB_PORT = 5432
DB_NAME = "mimic_iv_demo"

connection_url = URL.create(
    drivername="postgresql+psycopg2",
    username=DB_USER,
    password=DB_PASSWORD,
    host=DB_HOST,
    port=DB_PORT,
    database=DB_NAME,
)

engine = create_engine(connection_url)

TABLES = {
    "hosp": [
        "patients",
        "admissions",
        "diagnoses_icd",
        "d_icd_diagnoses",
        "procedures_icd",
        "d_icd_procedures",
        "prescriptions",
        "labevents",
        "d_labitems",
        "transfers",
    ],
    "icu": [
        "icustays",
        "chartevents",
        "d_items",
        "inputevents",
        "outputevents",
        "procedureevents",
        "datetimeevents",
    ],
}

# =========================
# LOAD CSV FILES
# =========================

for schema, tables in TABLES.items():
    for table in tables:
        csv_path = os.path.join(ROOT, schema, f"{table}.csv")

        if not os.path.exists(csv_path):
            print(f"Skipping missing file: {csv_path}")
            continue

        print(f"Loading {schema}.{table}...")

        df = pd.read_csv(csv_path, low_memory=False)

        df.to_sql(
            name=table,
            con=engine,
            schema=schema,
            if_exists="replace",
            index=False,
            chunksize=5000,
        )

        print(f"Loaded {schema}.{table}: {len(df)} rows")

print("Done.")