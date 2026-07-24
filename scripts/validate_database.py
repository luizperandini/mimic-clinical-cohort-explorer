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
# REQUIRED-FIELD VALIDATION RULES
# ============================================================

REQUIRED_FIELDS = {
    "hosp": {
        "patients": [
            "subject_id",
        ],
        "admissions": [
            "subject_id",
            "hadm_id",
        ],
    },
    "icu": {
        "icustays": [
            "subject_id",
            "hadm_id",
            "stay_id",
        ],
        "chartevents": [
            "subject_id",
            "hadm_id",
            "stay_id",
        ],
    },
}

REPORT_COLUMNS = [
    "schema",
    "table",
    "column",
    "check",
    "row_count",
    "checked_rows",
    "null_count",
    "null_percentage",
    "key_columns",
    "duplicate_group_count",
    "duplicate_row_count",
    "duplicate_percentage",
    "status",
    "message",
]


# ============================================================
# UNIQUE-KEY VALIDATION RULES
# ============================================================

UNIQUE_KEYS = {
    "hosp": {
        "patients": [
            "subject_id",
        ],
        "admissions": [
            "hadm_id",
        ],
    },
    "icu": {
        "icustays": [
            "stay_id",
        ],
    },
}

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

def count_null_values(
    engine: Engine,
    schema_name: str,
    table_name: str,
    column_name: str,
) -> tuple[int, int, float]:
    """
    Count total rows and SQL NULL values for one database column.

    Returns
    -------
    tuple[int, int, float]
        The number of checked rows, number of null values,
        and percentage of null values.
    """

    qualified_table_name = build_qualified_table_name(
        engine=engine,
        schema_name=schema_name,
        table_name=table_name,
    )

    preparer = engine.dialect.identifier_preparer
    quoted_column_name = preparer.quote(column_name)

    query = text(
        f"""
        SELECT
            COUNT(*) AS checked_rows,
            COUNT(*) FILTER (
                WHERE {quoted_column_name} IS NULL
            ) AS null_count
        FROM {qualified_table_name}
        """
    )

    with engine.connect() as connection:
        result = connection.execute(query).mappings().one()

    checked_rows = int(result["checked_rows"])
    null_count = int(result["null_count"])

    if checked_rows == 0:
        null_percentage = 0.0
    else:
        null_percentage = round(
            (null_count / checked_rows) * 100,
            4,
        )

    return checked_rows, null_count, null_percentage


def count_duplicate_keys(
    engine: Engine,
    schema_name: str,
    table_name: str,
    key_columns: list[str],
) -> tuple[int, int, int, float]:
    """
    Count duplicate key groups and extra duplicate rows.

    Parameters
    ----------
    engine
        Active SQLAlchemy database engine.
    schema_name
        PostgreSQL schema containing the table.
    table_name
        Table being validated.
    key_columns
        Column or columns expected to uniquely identify each row.

    Returns
    -------
    tuple[int, int, int, float]
        Checked rows, duplicate groups, extra duplicate rows,
        and duplicate-row percentage.
    """

    qualified_table_name = build_qualified_table_name(
        engine=engine,
        schema_name=schema_name,
        table_name=table_name,
    )

    preparer = engine.dialect.identifier_preparer

    quoted_key_columns = [
        preparer.quote(column_name)
        for column_name in key_columns
    ]

    key_expression = ", ".join(quoted_key_columns)

    query = text(
        f"""
        WITH duplicate_groups AS (
            SELECT
                {key_expression},
                COUNT(*) AS group_size
            FROM {qualified_table_name}
            GROUP BY {key_expression}
            HAVING COUNT(*) > 1
        )
        SELECT
            (
                SELECT COUNT(*)
                FROM {qualified_table_name}
            ) AS checked_rows,
            COUNT(*) AS duplicate_group_count,
            COALESCE(
                SUM(group_size - 1),
                0
            ) AS duplicate_row_count
        FROM duplicate_groups
        """
    )

    with engine.connect() as connection:
        result = connection.execute(query).mappings().one()

    checked_rows = int(result["checked_rows"])
    duplicate_group_count = int(
        result["duplicate_group_count"]
    )
    duplicate_row_count = int(
        result["duplicate_row_count"]
    )

    if checked_rows == 0:
        duplicate_percentage = 0.0
    else:
        duplicate_percentage = round(
            (duplicate_row_count / checked_rows) * 100,
            4,
        )

    return (
        checked_rows,
        duplicate_group_count,
        duplicate_row_count,
        duplicate_percentage,
    )

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
# REQUIRED-FIELD NULL VALIDATION
# ============================================================

def validate_required_fields(engine: Engine) -> pd.DataFrame:
    """
    Validate that critical identifier columns contain no SQL NULL values.

    Returns
    -------
    pandas.DataFrame
        One row for each required-field validation check.
    """

    inspector = inspect(engine)
    available_schemas = set(inspector.get_schema_names())

    results: list[dict[str, object]] = []

    for schema_name, table_rules in REQUIRED_FIELDS.items():
        logging.info(
            "Starting required-field validation for schema: %s",
            schema_name,
        )

        if schema_name not in available_schemas:
            for table_name, required_columns in table_rules.items():
                for column_name in required_columns:
                    results.append(
                        {
                            "schema": schema_name,
                            "table": table_name,
                            "column": column_name,
                            "check": "required_field_not_null",
                            "checked_rows": None,
                            "null_count": None,
                            "null_percentage": None,
                            "status": "FAIL",
                            "message": (
                                f"Required-field validation could not run "
                                f"because schema '{schema_name}' was not found."
                            ),
                        }
                    )

            continue

        available_tables = set(
            inspector.get_table_names(schema=schema_name)
        )

        for table_name, required_columns in table_rules.items():
            logging.info(
                "Validating required fields for table: %s.%s",
                schema_name,
                table_name,
            )

            if table_name not in available_tables:
                for column_name in required_columns:
                    results.append(
                        {
                            "schema": schema_name,
                            "table": table_name,
                            "column": column_name,
                            "check": "required_field_not_null",
                            "checked_rows": None,
                            "null_count": None,
                            "null_percentage": None,
                            "status": "FAIL",
                            "message": (
                                f"Required-field validation could not run "
                                f"because table "
                                f"'{schema_name}.{table_name}' was not found."
                            ),
                        }
                    )

                continue

            available_columns = {
                column["name"]
                for column in inspector.get_columns(
                    table_name=table_name,
                    schema=schema_name,
                )
            }

            for column_name in required_columns:
                logging.info(
                    "Checking null values: %s.%s.%s",
                    schema_name,
                    table_name,
                    column_name,
                )

                if column_name not in available_columns:
                    results.append(
                        {
                            "schema": schema_name,
                            "table": table_name,
                            "column": column_name,
                            "check": "required_field_not_null",
                            "checked_rows": None,
                            "null_count": None,
                            "null_percentage": None,
                            "status": "FAIL",
                            "message": (
                                f"Required column "
                                f"'{schema_name}.{table_name}.{column_name}' "
                                "was not found."
                            ),
                        }
                    )

                    continue

                try:
                    (
                        checked_rows,
                        null_count,
                        null_percentage,
                    ) = count_null_values(
                        engine=engine,
                        schema_name=schema_name,
                        table_name=table_name,
                        column_name=column_name,
                    )

                    if null_count == 0:
                        status = "PASS"
                        message = (
                            f"Column "
                            f"'{schema_name}.{table_name}.{column_name}' "
                            f"contains no null values across "
                            f"{checked_rows:,} rows."
                        )
                    else:
                        status = "FAIL"
                        message = (
                            f"Column "
                            f"'{schema_name}.{table_name}.{column_name}' "
                            f"contains {null_count:,} null values "
                            f"({null_percentage:.4f}%)."
                        )

                    results.append(
                        {
                            "schema": schema_name,
                            "table": table_name,
                            "column": column_name,
                            "check": "required_field_not_null",
                            "checked_rows": checked_rows,
                            "null_count": null_count,
                            "null_percentage": null_percentage,
                            "status": status,
                            "message": message,
                        }
                    )

                except Exception as error:
                    logging.exception(
                        "Unable to validate null values for %s.%s.%s",
                        schema_name,
                        table_name,
                        column_name,
                    )

                    results.append(
                        {
                            "schema": schema_name,
                            "table": table_name,
                            "column": column_name,
                            "check": "required_field_not_null",
                            "checked_rows": None,
                            "null_count": None,
                            "null_percentage": None,
                            "status": "FAIL",
                            "message": (
                                "Null validation could not be completed: "
                                f"{error}"
                            ),
                        }
                    )

    return pd.DataFrame(results)


# ============================================================
# UNIQUE-KEY DUPLICATE VALIDATION
# ============================================================

def validate_unique_keys(engine: Engine) -> pd.DataFrame:
    """
    Validate that configured logical keys contain no duplicates.

    Returns
    -------
    pandas.DataFrame
        One row for each unique-key validation check.
    """

    inspector = inspect(engine)
    available_schemas = set(inspector.get_schema_names())

    results: list[dict[str, object]] = []

    for schema_name, table_rules in UNIQUE_KEYS.items():
        logging.info(
            "Starting unique-key validation for schema: %s",
            schema_name,
        )

        if schema_name not in available_schemas:
            for table_name, key_columns in table_rules.items():
                key_label = ", ".join(key_columns)

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "key_columns": key_label,
                        "check": "unique_key_no_duplicates",
                        "checked_rows": None,
                        "duplicate_group_count": None,
                        "duplicate_row_count": None,
                        "duplicate_percentage": None,
                        "status": "FAIL",
                        "message": (
                            "Unique-key validation could not run "
                            f"because schema '{schema_name}' "
                            "was not found."
                        ),
                    }
                )

            continue

        available_tables = set(
            inspector.get_table_names(schema=schema_name)
        )

        for table_name, key_columns in table_rules.items():
            key_label = ", ".join(key_columns)

            logging.info(
                "Validating unique key for table: %s.%s (%s)",
                schema_name,
                table_name,
                key_label,
            )

            if table_name not in available_tables:
                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "key_columns": key_label,
                        "check": "unique_key_no_duplicates",
                        "checked_rows": None,
                        "duplicate_group_count": None,
                        "duplicate_row_count": None,
                        "duplicate_percentage": None,
                        "status": "FAIL",
                        "message": (
                            "Unique-key validation could not run "
                            f"because table "
                            f"'{schema_name}.{table_name}' "
                            "was not found."
                        ),
                    }
                )

                continue

            available_columns = {
                column["name"]
                for column in inspector.get_columns(
                    table_name=table_name,
                    schema=schema_name,
                )
            }

            missing_columns = [
                column_name
                for column_name in key_columns
                if column_name not in available_columns
            ]

            if missing_columns:
                missing_label = ", ".join(missing_columns)

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "key_columns": key_label,
                        "check": "unique_key_no_duplicates",
                        "checked_rows": None,
                        "duplicate_group_count": None,
                        "duplicate_row_count": None,
                        "duplicate_percentage": None,
                        "status": "FAIL",
                        "message": (
                            "Unique-key validation could not run "
                            f"because the following columns were "
                            f"not found in "
                            f"'{schema_name}.{table_name}': "
                            f"{missing_label}."
                        ),
                    }
                )

                continue

            try:
                (
                    checked_rows,
                    duplicate_group_count,
                    duplicate_row_count,
                    duplicate_percentage,
                ) = count_duplicate_keys(
                    engine=engine,
                    schema_name=schema_name,
                    table_name=table_name,
                    key_columns=key_columns,
                )

                if checked_rows == 0:
                    status = "WARNING"
                    message = (
                        f"Unique key '{key_label}' could not be "
                        f"meaningfully assessed because "
                        f"'{schema_name}.{table_name}' is empty."
                    )

                elif duplicate_row_count == 0:
                    status = "PASS"
                    message = (
                        f"Unique key '{key_label}' contains no "
                        f"duplicates across {checked_rows:,} rows "
                        f"in '{schema_name}.{table_name}'."
                    )

                else:
                    status = "FAIL"
                    message = (
                        f"Unique key '{key_label}' contains "
                        f"{duplicate_group_count:,} duplicate groups "
                        f"and {duplicate_row_count:,} extra rows "
                        f"({duplicate_percentage:.4f}%) in "
                        f"'{schema_name}.{table_name}'."
                    )

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "key_columns": key_label,
                        "check": "unique_key_no_duplicates",
                        "checked_rows": checked_rows,
                        "duplicate_group_count": (
                            duplicate_group_count
                        ),
                        "duplicate_row_count": (
                            duplicate_row_count
                        ),
                        "duplicate_percentage": (
                            duplicate_percentage
                        ),
                        "status": status,
                        "message": message,
                    }
                )

            except Exception as error:
                logging.exception(
                    "Unable to validate unique key for %s.%s",
                    schema_name,
                    table_name,
                )

                results.append(
                    {
                        "schema": schema_name,
                        "table": table_name,
                        "key_columns": key_label,
                        "check": "unique_key_no_duplicates",
                        "checked_rows": None,
                        "duplicate_group_count": None,
                        "duplicate_row_count": None,
                        "duplicate_percentage": None,
                        "status": "FAIL",
                        "message": (
                            "Unique-key validation could not be "
                            f"completed: {error}"
                        ),
                    }
                )

    return pd.DataFrame(results)


# ============================================================
# REPORTING
# ============================================================

def save_validation_report(results: pd.DataFrame) -> None:
    """
    Save validation results as a CSV file using a consistent column order.
    """

    REPORT_DIRECTORY.mkdir(parents=True, exist_ok=True)

    ordered_results = results.reindex(columns=REPORT_COLUMNS)

    ordered_results.to_csv(
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
        inventory_results = validate_database_inventory(engine)
        required_field_results = validate_required_fields(engine)
        unique_key_results = validate_unique_keys(engine)

        results = pd.concat(
            [
                inventory_results,
                required_field_results,
                unique_key_results,
            ],
            ignore_index=True,
            sort=False,
        )

        save_validation_report(results)
        print_validation_summary(results)

        logging.info("Database validation completed.")

    finally:
        engine.dispose()
        logging.info("Database connection closed.")


if __name__ == "__main__":
    main()