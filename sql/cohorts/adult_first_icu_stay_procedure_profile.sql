-- Adult First ICU Stay Cohort
-- Procedure data profiling
--
-- Purpose:
-- Understand the grain, coding structure, and duplication risk of the
-- procedure tables before integrating procedure data with the cohort.
--
-- This query does not modify the cohort definition.

\pset pager off

\echo ''
\echo '============================================================'
\echo '1. PROCEDURE SOURCE COLUMNS'
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
        'procedures_icd',
        'd_icd_procedures'
    )
ORDER BY
    table_name,
    ordinal_position;


\echo ''
\echo '============================================================'
\echo '2. PROCEDURE TABLE SIZE AND GRAIN'
\echo '============================================================'

SELECT
    COUNT(*) AS procedure_rows,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(DISTINCT hadm_id) AS unique_admissions,
    COUNT(DISTINCT icd_code) AS unique_icd_codes
FROM hosp.procedures_icd;


\echo ''
\echo '============================================================'
\echo '3. ICD VERSION DISTRIBUTION'
\echo '============================================================'

SELECT
    icd_version,
    COUNT(*) AS procedure_rows,
    COUNT(DISTINCT hadm_id) AS admission_count,
    COUNT(DISTINCT icd_code) AS unique_codes
FROM hosp.procedures_icd
GROUP BY icd_version
ORDER BY icd_version;


\echo ''
\echo '============================================================'
\echo '4. PROCEDURES PER ADMISSION'
\echo '============================================================'

WITH procedures_per_admission AS (
    SELECT
        hadm_id,
        COUNT(*) AS procedure_count
    FROM hosp.procedures_icd
    GROUP BY hadm_id
)

SELECT
    COUNT(*) AS admissions_with_procedures,
    MIN(procedure_count) AS minimum_procedures,
    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY procedure_count)::numeric,
        1
    ) AS median_procedures,
    ROUND(
        AVG(procedure_count)::numeric,
        1
    ) AS mean_procedures,
    MAX(procedure_count) AS maximum_procedures
FROM procedures_per_admission;


\echo ''
\echo '============================================================'
\echo '5. MULTIPLE PROCEDURES PER ADMISSION'
\echo '============================================================'

WITH procedures_per_admission AS (
    SELECT
        hadm_id,
        COUNT(*) AS procedure_count
    FROM hosp.procedures_icd
    GROUP BY hadm_id
)

SELECT
    COUNT(*) AS admissions_with_multiple_procedures
FROM procedures_per_admission
WHERE procedure_count > 1;


\echo ''
\echo '============================================================'
\echo '6. SEQUENCE NUMBER PROFILE'
\echo '============================================================'

SELECT
    seq_num,
    COUNT(*) AS procedure_rows
FROM hosp.procedures_icd
GROUP BY seq_num
ORDER BY seq_num
LIMIT 20;


\echo ''
\echo '============================================================'
\echo '7. POSSIBLE DUPLICATE PROCEDURE ROWS'
\echo '============================================================'

WITH duplicate_groups AS (
    SELECT
        subject_id,
        hadm_id,
        seq_num,
        chartdate,
        icd_code,
        icd_version,
        COUNT(*) AS duplicate_count
    FROM hosp.procedures_icd
    GROUP BY
        subject_id,
        hadm_id,
        seq_num,
        chartdate,
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
\echo '8. PROCEDURE DICTIONARY MATCH RATE'
\echo '============================================================'

SELECT
    COUNT(*) AS procedure_rows,
    COUNT(d.long_title) AS rows_with_dictionary_match,
    COUNT(*) - COUNT(d.long_title) AS rows_without_dictionary_match,
    ROUND(
        (
            100.0 * COUNT(d.long_title)
            / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS dictionary_match_pct
FROM hosp.procedures_icd AS p
LEFT JOIN hosp.d_icd_procedures AS d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version;


\echo ''
\echo '============================================================'
\echo '9. SAMPLE PROCEDURE RECORDS'
\echo '============================================================'

SELECT
    p.subject_id,
    p.hadm_id,
    p.seq_num,
    p.chartdate,
    p.icd_code,
    p.icd_version,
    d.long_title
FROM hosp.procedures_icd AS p
LEFT JOIN hosp.d_icd_procedures AS d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
ORDER BY
    p.hadm_id,
    p.seq_num,
    p.chartdate
LIMIT 20;
