-- Adult First ICU Stay Cohort
-- Diagnosis data profiling
--
-- Purpose:
-- Understand the grain, coding structure, and duplication risk of the
-- diagnosis tables before enriching the one-row-per-patient cohort.
--
-- This query does not yet modify the cohort definition.

\pset pager off

\echo ''
\echo '============================================================'
\echo '1. DIAGNOSIS SOURCE COLUMNS'
\echo '============================================================'

SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    data_type
FROM information_schema.columns
WHERE
    table_schema = 'hosp'
    AND table_name IN (
        'diagnoses_icd',
        'd_icd_diagnoses'
    )
ORDER BY
    table_name,
    ordinal_position;


\echo ''
\echo '============================================================'
\echo '2. DIAGNOSIS TABLE SIZE AND GRAIN'
\echo '============================================================'

SELECT
    COUNT(*) AS diagnosis_rows,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(DISTINCT hadm_id) AS unique_admissions,
    COUNT(DISTINCT icd_code) AS unique_icd_codes
FROM hosp.diagnoses_icd;


\echo ''
\echo '============================================================'
\echo '3. ICD VERSION DISTRIBUTION'
\echo '============================================================'

SELECT
    icd_version,
    COUNT(*) AS diagnosis_rows,
    COUNT(DISTINCT hadm_id) AS admission_count,
    COUNT(DISTINCT icd_code) AS unique_codes
FROM hosp.diagnoses_icd
GROUP BY icd_version
ORDER BY icd_version;


\echo ''
\echo '============================================================'
\echo '4. DIAGNOSES PER ADMISSION'
\echo '============================================================'

WITH diagnoses_per_admission AS (
    SELECT
        hadm_id,
        COUNT(*) AS diagnosis_count
    FROM hosp.diagnoses_icd
    GROUP BY hadm_id
)

SELECT
    COUNT(*) AS admissions_with_diagnoses,
    MIN(diagnosis_count) AS minimum_diagnoses,
    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY diagnosis_count)::numeric,
        1
    ) AS median_diagnoses,
    ROUND(
        AVG(diagnosis_count)::numeric,
        1
    ) AS mean_diagnoses,
    MAX(diagnosis_count) AS maximum_diagnoses
FROM diagnoses_per_admission;


\echo ''
\echo '============================================================'
\echo '5. MULTIPLE DIAGNOSES PER ADMISSION'
\echo '============================================================'

WITH diagnoses_per_admission AS (
    SELECT
        hadm_id,
        COUNT(*) AS diagnosis_count
    FROM hosp.diagnoses_icd
    GROUP BY hadm_id
)

SELECT
    COUNT(*) AS admissions_with_multiple_diagnoses
FROM diagnoses_per_admission
WHERE diagnosis_count > 1;


\echo ''
\echo '============================================================'
\echo '6. SEQUENCE NUMBER PROFILE'
\echo '============================================================'

SELECT
    seq_num,
    COUNT(*) AS diagnosis_rows
FROM hosp.diagnoses_icd
GROUP BY seq_num
ORDER BY seq_num
LIMIT 20;


\echo ''
\echo '============================================================'
\echo '7. POSSIBLE DUPLICATE DIAGNOSIS ROWS'
\echo '============================================================'

WITH duplicate_groups AS (
    SELECT
        subject_id,
        hadm_id,
        seq_num,
        icd_code,
        icd_version,
        COUNT(*) AS duplicate_count
    FROM hosp.diagnoses_icd
    GROUP BY
        subject_id,
        hadm_id,
        seq_num,
        icd_code,
        icd_version
    HAVING COUNT(*) > 1
)

SELECT
    COUNT(*) AS duplicate_groups,
    COALESCE(
        SUM(duplicate_count - 1),
        0
    ) AS excess_duplicate_rows
FROM duplicate_groups;


\echo ''
\echo '============================================================'
\echo '8. DIAGNOSIS DICTIONARY MATCH RATE'
\echo '============================================================'

SELECT
    COUNT(*) AS diagnosis_rows,
    COUNT(d.long_title) AS rows_with_dictionary_match,
    COUNT(*) - COUNT(d.long_title) AS rows_without_dictionary_match,
    ROUND(
        (
            100.0 * COUNT(d.long_title)
            / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS dictionary_match_pct
FROM hosp.diagnoses_icd AS dx
LEFT JOIN hosp.d_icd_diagnoses AS d
    ON dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version;


\echo ''
\echo '============================================================'
\echo '9. SAMPLE DIAGNOSIS RECORDS'
\echo '============================================================'

SELECT
    dx.subject_id,
    dx.hadm_id,
    dx.seq_num,
    dx.icd_code,
    dx.icd_version,
    d.long_title
FROM hosp.diagnoses_icd AS dx
LEFT JOIN hosp.d_icd_diagnoses AS d
    ON dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
ORDER BY
    dx.hadm_id,
    dx.seq_num
LIMIT 20;
