# Adult First ICU Stay Cohort

## Status

Feasibility reviewed on August 2, 2026.

The initial cohort design is approved for implementation as reusable SQL.

## Clinical Question

Among adult patients with an ICU stay lasting at least 24 hours, what are the
demographic, hospital-admission, ICU-stay, and diagnosis characteristics of
their first eligible ICU stay?

## Cohort Grain

One row per patient.

Each row represents the patient's earliest ICU stay that satisfies all
eligibility criteria.

## Index Event

The index event is the admission time (`intime`) of the patient's first
eligible ICU stay.

## Source Tables

- `hosp.patients`
- `hosp.admissions`
- `hosp.diagnoses_icd`
- `hosp.d_icd_diagnoses`
- `icu.icustays`

Diagnosis tables will initially be used for cohort characterization rather
than eligibility.

## Candidate Inclusion Criteria

1. The record exists in `icu.icustays`.
2. The ICU stay links to a valid hospital admission.
3. The hospital admission links to a valid patient.
4. The patient is at least 18 years old at hospital admission.
5. The ICU stay lasts at least 24 hours.
6. The record is the patient's earliest eligible ICU stay.

## Candidate Exclusion Criteria

1. ICU stays without a valid patient or hospital-admission relationship.
2. Patients younger than 18 years at hospital admission.
3. ICU stays shorter than 24 hours.
4. Chronologically invalid ICU stays.
5. Additional eligible ICU stays after the patient's first eligible stay.

## Planned Attrition Steps

1. All ICU-stay records.
2. ICU stays linked to a hospital admission.
3. ICU stays linked to a patient.
4. Adult ICU stays.
5. ICU stays lasting at least 24 hours.
6. First eligible ICU stay per patient.
7. Final cohort.

## Planned Cohort Attributes

The final design may include:

- `subject_id`
- `hadm_id`
- `stay_id`
- sex
- age at hospital admission
- admission type
- race
- insurance
- marital status
- hospital admission and discharge times
- hospital length of stay
- ICU admission and discharge times
- ICU length of stay
- first and last ICU care units
- in-hospital mortality indicator

The exact output columns will be finalized after feasibility analysis.

## Important Grain Constraint

Diagnosis data contain multiple records per hospital admission.

Diagnosis tables must not be joined directly to the one-row-per-patient cohort
without aggregation or another explicit strategy, because doing so would
duplicate cohort rows.

## Design Decisions After Feasibility Review

The preliminary feasibility analysis supported the following decisions:

- cohort grain: one row per patient;
- index event: the earliest eligible ICU stay;
- adult threshold: age at hospital admission greater than or equal to 18 years;
- minimum ICU length of stay: 1.0 day;
- valid patient and hospital-admission relationships are required;
- ICU discharge must occur after ICU admission;
- diagnosis data will initially be used for cohort characterization rather
  than eligibility.

Explicit timestamp casts are temporarily required because the current
PostgreSQL database stores several date-time columns as text. The ETL loader
and database column types will be reviewed as a separate improvement after
Sprint 4.

## Feasibility Results

The feasibility query evaluated 140 ICU stays from 100 patients and 128
hospital admissions.

| Step | Selection criterion | ICU stays | Patients | Admissions |
|---:|---|---:|---:|---:|
| 1 | All ICU stays | 140 | 100 | 128 |
| 2 | Linked to a valid admission | 140 | 100 | 128 |
| 3 | Linked to a valid patient | 140 | 100 | 128 |
| 4 | Valid ICU chronology | 140 | 100 | 128 |
| 5 | Adult at hospital admission | 140 | 100 | 128 |
| 6 | ICU length of stay at least 24 hours | 117 | 88 | 109 |
| 7 | First eligible ICU stay per patient | 88 | 88 | 88 |

The 24-hour criterion retained 88 of the 100 available ICU patients. This
provides an adequate sample for the MIMIC-IV Demo while excluding very short
ICU stays.

The preliminary final cohort contained:

- 88 rows;
- 88 unique patients;
- 88 unique hospital admissions;
- 88 unique ICU stays;
- minimum age of 21 years;
- median age of 63 years;
- maximum age of 92 years;
- minimum ICU length of stay of 1.04 days;
- median ICU length of stay of 2.54 days;
- maximum ICU length of stay of 20.53 days.

The matching row, patient, admission, and ICU-stay counts support the intended
one-row-per-patient grain.

## Remaining Open Decisions

The following decisions will be addressed during cohort enrichment and
reporting:

- which final analytical columns should be exported;
- how diagnosis data should be represented without changing the cohort grain;
- which descriptive statistics should appear in the cohort summary;
- whether diagnosis data should be exported as a separate long-form dataset.
## Planned Validation Rules

The completed cohort should verify:

- one row per patient;
- unique `subject_id`;
- non-null `subject_id`, `hadm_id`, and `stay_id`;
- age greater than or equal to 18;
- ICU length of stay greater than or equal to one day;
- ICU discharge occurring after ICU admission;
- valid patient and hospital-admission relationships;
- final row count matching the last attrition step.


