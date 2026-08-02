-- Adult First ICU Stay Cohort
-- Reproducible cohort attrition report
--
-- Purpose:
-- Report population counts, exclusions, and retention at every cohort
-- selection step.
--
-- Note:
-- Explicit timestamp casts are temporarily required because several source
-- date-time columns are currently stored as text in PostgreSQL.

\pset pager off

WITH all_icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime::timestamp AS icu_intime,
        i.outtime::timestamp AS icu_outtime,
        i.los::double precision AS icu_los_days
    FROM icu.icustays AS i
),

linked_admissions AS (
    SELECT
        i.*,
        a.admittime::timestamp AS hospital_admittime
    FROM all_icu_stays AS i
    INNER JOIN hosp.admissions AS a
        ON i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
),

linked_patients AS (
    SELECT
        a.*,
        p.anchor_age
            + (
                EXTRACT(YEAR FROM a.hospital_admittime)::integer
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
        icu_intime IS NOT NULL
        AND icu_outtime IS NOT NULL
        AND icu_outtime > icu_intime
),

adult_stays AS (
    SELECT *
    FROM valid_chronology
    WHERE age_at_admission >= 18
),

duration_eligible_stays AS (
    SELECT *
    FROM adult_stays
    WHERE icu_los_days >= 1.0
),

ranked_eligible_stays AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY subject_id
            ORDER BY icu_intime, stay_id
        ) AS patient_stay_number
    FROM duration_eligible_stays
),

first_eligible_stay AS (
    SELECT *
    FROM ranked_eligible_stays
    WHERE patient_stay_number = 1
),

step_counts AS (
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
),

counts_with_previous AS (
    SELECT
        *,
        LAG(record_count) OVER (
            ORDER BY step_number
        ) AS previous_record_count,
        LAG(patient_count) OVER (
            ORDER BY step_number
        ) AS previous_patient_count,
        FIRST_VALUE(record_count) OVER (
            ORDER BY step_number
        ) AS baseline_record_count,
        FIRST_VALUE(patient_count) OVER (
            ORDER BY step_number
        ) AS baseline_patient_count
    FROM step_counts
)

SELECT
    step_number,
    attrition_step,
    record_count,
    CASE
        WHEN previous_record_count IS NULL THEN NULL
        ELSE previous_record_count - record_count
    END AS records_removed,
    patient_count,
    CASE
        WHEN previous_patient_count IS NULL THEN NULL
        ELSE previous_patient_count - patient_count
    END AS patients_removed,
    admission_count,
    ROUND(
        (
            100.0 * record_count
            / NULLIF(baseline_record_count, 0)
        )::numeric,
        1
    ) AS record_retention_from_baseline_pct,
    ROUND(
        (
            100.0 * patient_count
            / NULLIF(baseline_patient_count, 0)
        )::numeric,
        1
    ) AS patient_retention_from_baseline_pct,
    CASE
        WHEN previous_record_count IS NULL THEN NULL
        ELSE ROUND(
            (
                100.0 * record_count
                / NULLIF(previous_record_count, 0)
            )::numeric,
            1
        )
    END AS record_retention_from_previous_pct
FROM counts_with_previous
ORDER BY step_number;
