-- Adult First ICU Stay Cohort
-- Preliminary feasibility analysis
--
-- Purpose:
-- 1. Confirm that the required source columns exist.
-- 2. Calculate sequential cohort attrition.
-- 3. Summarize the preliminary final cohort.
--
-- This is exploratory SQL and not yet the final production cohort query.

\pset pager off

\echo ''
\echo '============================================================'
\echo '1. REQUIRED SOURCE COLUMNS'
\echo '============================================================'

SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    data_type
FROM information_schema.columns
WHERE
    (
        table_schema = 'hosp'
        AND table_name = 'patients'
        AND column_name IN (
            'subject_id',
            'gender',
            'anchor_age',
            'anchor_year'
        )
    )
    OR
    (
        table_schema = 'hosp'
        AND table_name = 'admissions'
        AND column_name IN (
            'subject_id',
            'hadm_id',
            'admittime',
            'dischtime',
            'admission_type',
            'race',
            'insurance',
            'marital_status',
            'hospital_expire_flag'
        )
    )
    OR
    (
        table_schema = 'icu'
        AND table_name = 'icustays'
        AND column_name IN (
            'subject_id',
            'hadm_id',
            'stay_id',
            'first_careunit',
            'last_careunit',
            'intime',
            'outtime',
            'los'
        )
    )
ORDER BY
    table_schema,
    table_name,
    ordinal_position;


\echo ''
\echo '============================================================'
\echo '2. PRELIMINARY COHORT ATTRITION'
\echo '============================================================'

WITH all_icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.first_careunit,
        i.last_careunit,
        i.intime::timestamp AS intime,
        i.outtime::timestamp AS outtime,
        i.los
    FROM icu.icustays AS i
),

linked_admissions AS (
    SELECT
        i.*,
        a.admittime::timestamp AS admittime,
        a.dischtime::timestamp AS dischtime,
        a.admission_type,
        a.race,
        a.insurance,
        a.marital_status,
        a.hospital_expire_flag
    FROM all_icu_stays AS i
    INNER JOIN hosp.admissions AS a
        ON i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
),

linked_patients AS (
    SELECT
        a.*,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        p.anchor_age
            + (
                EXTRACT(YEAR FROM a.admittime::timestamp)::integer
                - p.anchor_year
            ) AS age_at_admission
    FROM linked_admissions AS a
    INNER JOIN hosp.patients AS p
        ON a.subject_id = p.subject_id
),

valid_chronology AS (
    SELECT *
    FROM linked_patients
    WHERE
        intime IS NOT NULL
        AND outtime IS NOT NULL
        AND outtime > intime
),

adult_stays AS (
    SELECT *
    FROM valid_chronology
    WHERE age_at_admission >= 18
),

duration_eligible_stays AS (
    SELECT *
    FROM adult_stays
    WHERE los >= 1.0
),

ranked_eligible_stays AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY subject_id
            ORDER BY intime, stay_id
        ) AS patient_stay_number
    FROM duration_eligible_stays
),

first_eligible_stay AS (
    SELECT *
    FROM ranked_eligible_stays
    WHERE patient_stay_number = 1
)

SELECT
    1 AS step_number,
    'All ICU stays' AS attrition_step,
    COUNT(*) AS record_count,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count
FROM all_icu_stays

UNION ALL

SELECT
    2,
    'Linked to a valid admission',
    COUNT(*),
    COUNT(DISTINCT subject_id),
    COUNT(DISTINCT hadm_id)
FROM linked_admissions

UNION ALL

SELECT
    3,
    'Linked to a valid patient',
    COUNT(*),
    COUNT(DISTINCT subject_id),
    COUNT(DISTINCT hadm_id)
FROM linked_patients

UNION ALL

SELECT
    4,
    'Valid ICU chronology',
    COUNT(*),
    COUNT(DISTINCT subject_id),
    COUNT(DISTINCT hadm_id)
FROM valid_chronology

UNION ALL

SELECT
    5,
    'Adult at hospital admission',
    COUNT(*),
    COUNT(DISTINCT subject_id),
    COUNT(DISTINCT hadm_id)
FROM adult_stays

UNION ALL

SELECT
    6,
    'ICU length of stay at least 24 hours',
    COUNT(*),
    COUNT(DISTINCT subject_id),
    COUNT(DISTINCT hadm_id)
FROM duration_eligible_stays

UNION ALL

SELECT
    7,
    'First eligible ICU stay per patient',
    COUNT(*),
    COUNT(DISTINCT subject_id),
    COUNT(DISTINCT hadm_id)
FROM first_eligible_stay

ORDER BY step_number;


\echo ''
\echo '============================================================'
\echo '3. PRELIMINARY FINAL COHORT SUMMARY'
\echo '============================================================'

WITH eligible_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime::timestamp AS intime,
        i.outtime::timestamp AS outtime,
        i.los,
        p.gender,
        p.anchor_age
            + (
                EXTRACT(YEAR FROM a.admittime::timestamp)::integer
                - p.anchor_year
            ) AS age_at_admission,
        ROW_NUMBER() OVER (
            PARTITION BY i.subject_id
            ORDER BY i.intime::timestamp, i.stay_id
        ) AS patient_stay_number
    FROM icu.icustays AS i
    INNER JOIN hosp.admissions AS a
        ON i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
    INNER JOIN hosp.patients AS p
        ON i.subject_id = p.subject_id
    WHERE
        i.intime IS NOT NULL
        AND i.outtime IS NOT NULL
        AND i.outtime::timestamp > i.intime::timestamp
        AND i.los >= 1.0
        AND (
            p.anchor_age
            + (
                EXTRACT(YEAR FROM a.admittime::timestamp)::integer
                - p.anchor_year
            )
        ) >= 18
),

final_cohort AS (
    SELECT *
    FROM eligible_stays
    WHERE patient_stay_number = 1
)

SELECT
    COUNT(*) AS final_rows,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(DISTINCT hadm_id) AS unique_admissions,
    COUNT(DISTINCT stay_id) AS unique_icu_stays,
    MIN(age_at_admission) AS minimum_age,
    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY age_at_admission)::numeric,
        1
    ) AS median_age,
    MAX(age_at_admission) AS maximum_age,
    ROUND(MIN(los)::numeric, 2) AS minimum_icu_los_days,
    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY los)::numeric,
        2
    ) AS median_icu_los_days,
    ROUND(MAX(los)::numeric, 2) AS maximum_icu_los_days
FROM final_cohort;

