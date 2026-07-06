import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

PROJECT_ROOT = Path(__file__).resolve().parents[1]

MIMIC_ROOT = Path(
    r"C:\Users\lpera\Dropbox\Dados e IA\MIMIC_Project"
)

DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME")

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