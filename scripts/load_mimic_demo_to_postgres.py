import logging
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

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
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
        logging.warning("Skipping missing file: %s", csv_path)
        return 0

    logging.info("Loading %s.%s...", schema, table)

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

    logging.info("Loaded %s.%s: %s rows", schema, table, rows_loaded)

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
    logging.info("===============================")
    logging.info("MIMIC-IV DEMO IMPORT SUMMARY")
    logging.info("===============================")

    for table_name, row_count in summary.items():
        logging.info("%-35s %10s rows", table_name, row_count)

    logging.info("-------------------------------")
    logging.info("Total tables processed: %s", len(summary))
    logging.info("Total rows loaded: %s", sum(summary.values()))
    logging.info("Elapsed time: %.2f seconds", elapsed_time)
    logging.info("===============================")


def main():
    """Main ETL workflow."""
    start_time = time.time()

    engine = create_database_engine()
    summary = load_all_tables(engine)

    elapsed_time = time.time() - start_time

    print_summary(summary, elapsed_time)


if __name__ == "__main__":
    main()