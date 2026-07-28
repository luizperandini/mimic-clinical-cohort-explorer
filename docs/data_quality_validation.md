# Data Quality and Database Validation

## Overview

Loading healthcare data into a database does not automatically make the
data trustworthy or analytically usable.

The `validate_database.py` script independently evaluates the PostgreSQL
database after the MIMIC-IV Demo ETL process has completed. It checks whether
the expected database objects exist and whether critical clinical records can
be reliably identified and linked.

The validation framework currently evaluates:

- database structure;
- table population;
- required identifier completeness;
- logical key uniqueness;
- referential integrity;
- overall database health.

The script produces both detailed and summarized validation reports.

---

## Why healthcare data validation matters

Healthcare data is highly relational.

A clinical observation may need to be connected to:

1. a patient;
2. a hospital admission;
3. an ICU stay;
4. a diagnosis, procedure, laboratory test, or treatment event.

A row can exist in the database and still be unusable if:

- a critical identifier is missing;
- the record is duplicated;
- the referenced patient or encounter does not exist;
- the table was loaded incorrectly;
- the table is unexpectedly empty.

These problems can affect:

- cohort identification;
- patient-level feature engineering;
- longitudinal analysis;
- clinical endpoint construction;
- real-world evidence studies;
- machine-learning model development;
- reproducibility of analytical results.

The validation framework is therefore executed separately from the ETL
loader. The loader imports data, while the validator independently assesses
the resulting database.

---

## Running the validator

Activate the project environment and run the script from the repository root:

```powershell
conda activate py312
python scripts\validate_database.py