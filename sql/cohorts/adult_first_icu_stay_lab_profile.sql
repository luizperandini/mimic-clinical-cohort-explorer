-- Adult First ICU Stay Cohort
-- Laboratory data profiling
--
-- Purpose:
-- Understand the structure, coverage, and repeated-measure characteristics
-- of laboratory data before selecting laboratory variables for the cohort.
--
-- This query does not modify the cohort definition.

\pset pager off

\echo ''
\echo '============================================================'
\echo '1. LABORATORY SOURCE COLUMNS'
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
        'labevents',
        'd_labitems'
    )
ORDER BY
    table_name,
    ordinal_position;


\echo ''
\echo '============================================================'
\echo '2. LABORATORY TABLE SIZE AND GRAIN'
\echo '============================================================'

SELECT
    COUNT(*) AS laboratory_rows,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(DISTINCT hadm_id) AS unique_admissions,
    COUNT(DISTINCT itemid) AS unique_lab_items
FROM hosp.labevents;


\echo ''
\echo '============================================================'
\echo '3. MISSING ADMISSION IDENTIFIERS'
\echo '============================================================'

SELECT
    COUNT(*) AS laboratory_rows,
    COUNT(*) FILTER (
        WHERE hadm_id IS NULL
    ) AS rows_without_hadm_id,
    ROUND(
        (
            100.0
            * COUNT(*) FILTER (WHERE hadm_id IS NULL)
            / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS rows_without_hadm_id_pct
FROM hosp.labevents;


\echo ''
\echo '============================================================'
\echo '4. NUMERIC RESULT COVERAGE'
\echo '============================================================'

SELECT
    COUNT(*) AS laboratory_rows,
    COUNT(valuenum) AS rows_with_numeric_value,
    COUNT(*) - COUNT(valuenum) AS rows_without_numeric_value,
    ROUND(
        (
            100.0
            * COUNT(valuenum)
            / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS numeric_value_pct
FROM hosp.labevents;


\echo ''
\echo '============================================================'
\echo '5. LAB DICTIONARY MATCH RATE'
\echo '============================================================'

SELECT
    COUNT(*) AS laboratory_rows,
    COUNT(d.label) AS rows_with_dictionary_match,
    COUNT(*) - COUNT(d.label) AS rows_without_dictionary_match,
    ROUND(
        (
            100.0
            * COUNT(d.label)
            / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS dictionary_match_pct
FROM hosp.labevents AS l
LEFT JOIN hosp.d_labitems AS d
    ON l.itemid = d.itemid;


\echo ''
\echo '============================================================'
\echo '6. MOST FREQUENT LABORATORY TESTS'
\echo '============================================================'

SELECT
    l.itemid,
    d.label,
    d.fluid,
    d.category,
    COUNT(*) AS measurement_count,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(DISTINCT l.hadm_id) AS admission_count
FROM hosp.labevents AS l
LEFT JOIN hosp.d_labitems AS d
    ON l.itemid = d.itemid
GROUP BY
    l.itemid,
    d.label,
    d.fluid,
    d.category
ORDER BY
    measurement_count DESC
LIMIT 30;


\echo ''
\echo '============================================================'
\echo '7. REPEATED MEASUREMENTS PER ADMISSION AND LAB ITEM'
\echo '============================================================'

WITH measurements_per_admission_item AS (
    SELECT
        hadm_id,
        itemid,
        COUNT(*) AS measurement_count
    FROM hosp.labevents
    WHERE hadm_id IS NOT NULL
    GROUP BY
        hadm_id,
        itemid
)

SELECT
    COUNT(*) AS admission_lab_pairs,
    COUNT(*) FILTER (
        WHERE measurement_count > 1
    ) AS repeated_admission_lab_pairs,
    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY measurement_count
            )::numeric,
        1
    ) AS median_measurements,
    ROUND(
        AVG(measurement_count)::numeric,
        1
    ) AS mean_measurements,
    MAX(measurement_count) AS maximum_measurements
FROM measurements_per_admission_item;


\echo ''
\echo '============================================================'
\echo '8. SAMPLE LABORATORY RECORDS'
\echo '============================================================'

SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    d.label,
    l.charttime,
    l.value,
    l.valuenum,
    l.valueuom,
    l.flag
FROM hosp.labevents AS l
LEFT JOIN hosp.d_labitems AS d
    ON l.itemid = d.itemid
ORDER BY
    l.subject_id,
    l.hadm_id,
    l.charttime
LIMIT 20;
