@'
# Adult First ICU Stay Cohort — Data Dictionary

## Purpose

This document describes the analysis-ready variables included in the Adult
First ICU Stay Cohort.

The cohort grain is one row per patient, representing the patient's earliest
eligible ICU stay.

Each variable is documented with its source, derivation, and analytical
purpose to support reproducibility and data lineage.

## Identifiers

| Variable | Source | Type | Description |
|---|---|---|---|
| `subject_id` | `hosp.patients.subject_id` / linked tables | Source | Unique patient identifier |
| `hadm_id` | `hosp.admissions.hadm_id` | Source | Unique hospital admission identifier |
| `stay_id` | `icu.icustays.stay_id` | Source | Unique ICU stay identifier |

## Patient Demographics

| Variable | Source | Type | Description |
|---|---|---|---|
| `gender` | `hosp.patients.gender` | Source | Recorded patient sex/gender field in MIMIC-IV |
| `age_at_admission` | `anchor_age`, `anchor_year`, `admittime` | Derived | Estimated patient age at hospital admission |

## Hospital Admission Characteristics

| Variable | Source | Type | Description |
|---|---|---|---|
| `admission_type` | `hosp.admissions.admission_type` | Source | Hospital admission category |
| `race` | `hosp.admissions.race` | Source | Recorded race field for the admission |
| `insurance` | `hosp.admissions.insurance` | Source | Recorded insurance category |
| `marital_status` | `hosp.admissions.marital_status` | Source | Recorded marital status |
| `hospital_expire_flag` | `hosp.admissions.hospital_expire_flag` | Source | Indicator of in-hospital mortality |
| `hospital_admittime` | `hosp.admissions.admittime` | Source with temporary cast | Hospital admission timestamp |
| `hospital_dischtime` | `hosp.admissions.dischtime` | Source with temporary cast | Hospital discharge timestamp |
| `hospital_los_days` | admission and discharge timestamps | Derived | Hospital length of stay in days |

## ICU Characteristics

| Variable | Source | Type | Description |
|---|---|---|---|
| `icu_intime` | `icu.icustays.intime` | Source with temporary cast | ICU admission timestamp |
| `icu_outtime` | `icu.icustays.outtime` | Source with temporary cast | ICU discharge timestamp |
| `icu_los_days` | `icu.icustays.los` | Source | ICU length of stay in days |
| `first_careunit` | `icu.icustays.first_careunit` | Source | First ICU care unit |
| `last_careunit` | `icu.icustays.last_careunit` | Source | Last ICU care unit |

## Cohort-Level Derived Logic

### Age at Hospital Admission

Age is estimated using:

```text
anchor_age + (admission_year - anchor_year)