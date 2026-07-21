from __future__ import annotations

import logging
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Engine, URL

from config import (
    DB_HOST,
    DB_NAME,
    DB_PASSWORD,
    DB_PORT,
    DB_USER,
    TABLES,
)

# ============================================================
# PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[1]

REPORT_DIRECTORY = PROJECT_ROOT / "reports" / "validation"
LOG_DIRECTORY = PROJECT_ROOT / "logs"

REPORT_FILE = REPORT_DIRECTORY / "database_inventory.csv"
LOG_FILE = LOG_DIRECTORY / "database_validation.log"


# ============================================================
# LOGGING
# ============================================================

def configure_logging() -> None:
    """
    Configure console and file logging for database validation.
    """

    LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[
            logging.FileHandler(LOG_FILE, encoding="utf-8"),
            logging.StreamHandler(),
        ],
    )


# ============================================================
# DATABASE CONNECTION
# ============================================================

def create_database_engine() -> Engine:
    """
    Validate database settings and create a SQLAlchemy engine.
    """

    database_settings = {
        "DB_USER": DB_USER,
        "DB_PASSWORD": DB_PASSWORD,
        "DB_HOST": DB_HOST,
        "DB_NAME": DB_NAME,
    }

    missing_settings = [
        setting_name
        for setting_name, setting_value in database_settings.items()
        if not setting_value
    ]

    if missing_settings:
        missing_list = ", ".join(missing_settings)

        raise RuntimeError(
            "Missing required database environment variables: "
            f"{missing_list}"
        )

    database_url = URL.create(
        drivername="postgresql+psycopg2",
        username=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
    )

    logging.info(
        "Creating database connection to %s:%s/%s.",
        DB_HOST,
        DB_PORT,
        DB_NAME,
    )

    return create_engine(
        database_url,
        pool_pre_ping=True,
    )


# ============================================================
# VALIDATION HELPERS
# ============================================================

def build_qualified_table_name(
    engine: Engine,
    schema_name: str,
    table_name: str,
) -> str:
    """
    Safely quote a schema and table name for use in a SQL statement.

    Table and schema names cannot be passed as normal SQL parameters,
    so SQLAlchemy's identifier preparer is used to quote them.
    """

    preparer = engine.dialect.identifier_preparer

    quoted_schema = preparer.quote_schema(schema_name)
    quoted_table = preparer.quote(table_name)

    return f"{quoted_schema}.{quoted_table}"


def count_table_rows(
    engine: Engine,
    schema_name: str,
    table_name: str,
) -> int:
    """
    Return the exact number of rows in a database table.
    """

    qualified_table_name = build_qualified_table_name(
        engine=engine,
        schema_name=schema_name,
        table_name=table_name,
    )

    query = text(
        f"SELECT COUNT(*) FROM {qualified_table_name}"
    )

    with engine.connect() as connection:
        row_count = connection.execute(query).scalar_one()

    return int(row_count)


# ============================================================
# DATABASE INVENTORY VALIDATION
# ============================================================

def validate_database_inventory(engine: Engine) -> pd.DataFrame:
    """
    Validate expected schemas and tables and collect their row counts.

    Returns
    -------
    pandas.DataFrame
        One row for each validation result.
    """

    inspector = inspect(engine)
    available_schemas = set(inspector.get_schema_names())

    results: list[dict[str, object]] = []

    for schema_name, expected_tables in TABLES.items():
        logging.info("Validating schema: %s", schema_name)

        if schema_name not in available_schemas:
            logging.error("Schema not found: %s", schema_name)

            results.append(
                {
                    "schema": schema_name,
                    "table": None,
                    "check": "schema_exists",
                    "row_count": None,
                    "status": "FAIL",
                    "message": f"Expected schema '{schema_name}' was not found.",
                }
            )

            # Tables cannot be checked when the entire schema is missing.
            continue

        results.append(
            {
                "schema": schema_name,
                "table": None,
                "check": "schema_exists",
                "row_count": None,
                "status": "PASS",
                "message": f"Schema '{schema_name}' exists.",
            }
        )

        available_tables = set(
            inspector.get_table_names(schema=schema_name)
        )

        for table_name in expected_tables:
            logging.info(
                "Validating table: %s.%s",
                schema_name,
                table_name,
            )

            if table_name not in available_tables:
                logging.error(
                    "Table not found: %s.%s",
                    schema_name,
                    table_name,
                )

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "check": "table_exists_and_has_rows",
                        "row_count": None,
                        "status": "FAIL",
                        "message": (
                            f"Expected table "
                            f"'{schema_name}.{table_name}' was not found."
                        ),
                    }
                )

                continue

            try:
                row_count = count_table_rows(
                    engine=engine,
                    schema_name=schema_name,
                    table_name=table_name,
                )

                if row_count == 0:
                    status = "WARNING"
                    message = (
                        f"Table '{schema_name}.{table_name}' exists "
                        "but contains no rows."
                    )
                else:
                    status = "PASS"
                    message = (
                        f"Table '{schema_name}.{table_name}' exists "
                        f"and contains {row_count:,} rows."
                    )

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "check": "table_exists_and_has_rows",
                        "row_count": row_count,
                        "status": status,
                        "message": message,
                    }
                )

            except Exception as error:
                logging.exception(
                    "Unable to count rows in %s.%s",
                    schema_name,
                    table_name,
                )

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "check": "table_exists_and_has_rows",
                        "row_count": None,
                        "status": "FAIL",
                        "message": (
                            "Table exists, but the row count could not "
                            f"be calculated: {error}"
                        ),
                    }
                )

    return pd.DataFrame(results)


# ============================================================
# REPORTING
# ============================================================

def save_validation_report(results: pd.DataFrame) -> None:
    """
    Save validation results as a CSV file.
    """

    REPORT_DIRECTORY.mkdir(parents=True, exist_ok=True)

    results.to_csv(
        REPORT_FILE,
        index=False,
        encoding="utf-8",
    )

    logging.info("Validation report saved to: %s", REPORT_FILE)


def print_validation_summary(results: pd.DataFrame) -> None:
    """
    Print a concise validation summary to the terminal.
    """

    status_counts = results["status"].value_counts()

    pass_count = int(status_counts.get("PASS", 0))
    warning_count = int(status_counts.get("WARNING", 0))
    fail_count = int(status_counts.get("FAIL", 0))

    table_results = results[results["table"].notna()]
    total_rows = int(table_results["row_count"].fillna(0).sum())

    print("\n" + "=" * 60)
    print("DATABASE VALIDATION SUMMARY")
    print("=" * 60)
    print(f"Checks completed : {len(results)}")
    print(f"Passed           : {pass_count}")
    print(f"Warnings         : {warning_count}")
    print(f"Failed           : {fail_count}")
    print(f"Total table rows : {total_rows:,}")
    print(f"Report           : {REPORT_FILE}")
    print("=" * 60)

    failed_checks = results[results["status"] == "FAIL"]

    if not failed_checks.empty:
        print("\nFAILED CHECKS")

        for _, row in failed_checks.iterrows():
            print(f"- {row['message']}")


# ============================================================
# MAIN
# ============================================================

def main() -> None:
    """
    Run the database inventory validation process.
    """

    configure_logging()

    logging.info("Starting database validation.")

    engine = create_database_engine()

    try:
        results = validate_database_inventory(engine)
        save_validation_report(results)
        print_validation_summary(results)

        logging.info("Database validation completed.")

    finally:
        engine.dispose()
        logging.info("Database connection closed.")


if __name__ == "__main__":
    main()