from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]

MIMIC_ROOT = Path(
    r"C:\Users\lpera\Dropbox\Dados e IA\MIMIC_Project"
)

DB_USER = "postgres"
DB_PASSWORD = "Paty2829@#.,"
DB_HOST = "localhost"
DB_PORT = 5432
DB_NAME = "mimic_iv_demo"

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