import logging
import time
from dataclasses import dataclass

import pandas as pd
from sqlalchemy import URL, create_engine, text
from sqlalchemy.exc import SQLAlchemyError

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


@dataclass
class TableLoadResult:
    schema: str
    table: str
    status: str
    rows_loaded: int = 0
    error: str | None = None


def create_database_engine():
    connection_url = URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
    )

    return create_engine(connection_url)


def test_database_connection(engine):
    logging.info("Testing PostgreSQL connection...")

    with engine.connect() as connection:
        result = connection.execute(text("SELECT 1"))
        result.scalar()

    logging.info("PostgreSQL connection successful.")


def ensure_schemas_exist(engine):
    logging.info("Ensuring required schemas exist...")

    with engine.begin() as connection:
        for schema in TABLES.keys():
            connection.execute(text(f"CREATE SCHEMA IF NOT EXISTS {schema};"))
            logging.info("Schema ready: %s", schema)


def load_table(engine, schema, table):
    csv_path = MIMIC_ROOT / schema / f"{table}.csv"

    if not csv_path.exists():
        message = f"Missing file: {csv_path}"
        logging.warning(message)
        return TableLoadResult(schema=schema, table=table, status="SKIPPED", error=message)

    try:
        logging.info("Loading %s.%s...", schema, table)

        df = pd.read_csv(csv_path, low_memory=False)

        df.to_sql(
            name=table,
            con=engine,
            schema=schema,
            if_exists="replace",
            index=False,
            chunksize=5000,
            method="multi",
        )

        rows_loaded = len(df)

        logging.info("Loaded %s.%s: %s rows", schema, table, rows_loaded)

        return TableLoadResult(
            schema=schema,
            table=table,
            status="SUCCESS",
            rows_loaded=rows_loaded,
        )

    except Exception as error:
        logging.exception("Failed to load %s.%s", schema, table)

        return TableLoadResult(
            schema=schema,
            table=table,
            status="FAILED",
            error=str(error),
        )


def load_all_tables(engine):
    results = []

    for schema, tables in TABLES.items():
        for table in tables:
            result = load_table(engine, schema, table)
            results.append(result)

    return results


def print_summary(results, elapsed_time):
    successful = [r for r in results if r.status == "SUCCESS"]
    skipped = [r for r in results if r.status == "SKIPPED"]
    failed = [r for r in results if r.status == "FAILED"]

    total_rows = sum(r.rows_loaded for r in successful)

    logging.info("")
    logging.info("=====================================================")
    logging.info("              MIMIC-IV DEMO ETL SUMMARY")
    logging.info("=====================================================")

    for result in results:
        table_name = f"{result.schema}.{result.table}"
        logging.info(
            "%-35s %-10s %10s rows",
            table_name,
            result.status,
            result.rows_loaded,
        )

    logging.info("-----------------------------------------------------")
    logging.info("Tables successful: %s", len(successful))
    logging.info("Tables skipped:    %s", len(skipped))
    logging.info("Tables failed:     %s", len(failed))
    logging.info("Total rows loaded: %s", total_rows)
    logging.info("Elapsed time:      %.2f seconds", elapsed_time)

    if failed:
        logging.error("ETL completed with failures.")
        for result in failed:
            logging.error("%s.%s failed: %s", result.schema, result.table, result.error)
    else:
        logging.info("ETL completed successfully.")

    logging.info("=====================================================")


def main():
    start_time = time.time()

    try:
        engine = create_database_engine()
        test_database_connection(engine)
        ensure_schemas_exist(engine)

        results = load_all_tables(engine)

        elapsed_time = time.time() - start_time
        print_summary(results, elapsed_time)

    except SQLAlchemyError as error:
        logging.exception("Database connection or SQLAlchemy error: %s", error)

    except Exception as error:
        logging.exception("Unexpected ETL error: %s", error)


if __name__ == "__main__":
    main()