import time

import pandas as pd
from sqlalchemy import URL, create_engine

from config import (
    DB_HOST,
    DB_NAME,
    DB_PASSWORD,
    DB_PORT,
    DB_USER,
    MIMIC_ROOT,
    TABLES,
)


def create_database_engine():
    """Create and return a SQLAlchemy database engine."""

    connection_url = URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
    )

    return create_engine(connection_url)


def load_table(engine, schema, table):
    """Load one CSV file into PostgreSQL."""

    csv_path = MIMIC_ROOT / schema / f"{table}.csv"

    if not csv_path.exists():
        print(f"Skipping missing file: {csv_path}")
        return 0

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

    rows_loaded = len(df)

    print(f"Loaded {schema}.{table}: {rows_loaded} rows")

    return rows_loaded


def load_all_tables(engine):
    """Load all configured MIMIC-IV demo tables."""

    summary = {}

    for schema, tables in TABLES.items():
        for table in tables:
            rows_loaded = load_table(engine, schema, table)
            summary[f"{schema}.{table}"] = rows_loaded

    return summary


def print_summary(summary, elapsed_time):
    """Print a summary of the import process."""

    print("\n===============================")
    print("MIMIC-IV DEMO IMPORT SUMMARY")
    print("===============================")

    for table_name, row_count in summary.items():
        print(f"{table_name:<35} {row_count:>10} rows")

    print("-------------------------------")
    print(f"Total tables processed: {len(summary)}")
    print(f"Total rows loaded: {sum(summary.values())}")
    print(f"Elapsed time: {elapsed_time:.2f} seconds")
    print("===============================\n")


def main():
    """Main ETL workflow."""

    start_time = time.time()

    engine = create_database_engine()
    summary = load_all_tables(engine)

    elapsed_time = time.time() - start_time

    print_summary(summary, elapsed_time)


if __name__ == "__main__":
    main()