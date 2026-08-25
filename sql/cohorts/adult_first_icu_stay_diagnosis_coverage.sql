-- Adult First ICU Stay Cohort
-- Diagnosis coverage within the final cohort
--
-- Purpose:
-- Measure diagnosis availability and row expansion specifically for the
-- 88 index hospital admissions selected by the cohort.

\pset pager off

WITH cohort AS (
    -- Reproduce the approved cohort identifiers only.
    WITH source_icu_stays AS (
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
        FROM source_icu_stays AS i
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

    eligible_stays AS (
        SELECT *
        FROM linked_patients
        WHERE
            icu_intime IS NOT NULL
            AND icu_outtime IS NOT NULL
            AND icu_outtime > icu_intime
            AND age_at_admission >= 18
            AND icu_los_days >= 1.0
    ),

    ranked_stays AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY subject_id
                ORDER BY icu_intime, stay_id
            ) AS patient_stay_number
        FROM eligible_stays
    )

    SELECT
        subject_id,
        hadm_id,
        stay_id
    FROM ranked_stays
    WHERE patient_stay_number = 1
),

cohort_diagnoses AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        dx.seq_num,
        dx.icd_code,
        dx.icd_version,
        d.long_title
    FROM cohort AS c
    LEFT JOIN hosp.diagnoses_icd AS dx
        ON c.subject_id = dx.subject_id
        AND c.hadm_id = dx.hadm_id
    LEFT JOIN hosp.d_icd_diagnoses AS d
        ON dx.icd_code = d.icd_code
        AND dx.icd_version = d.icd_version
),

diagnoses_per_cohort_admission AS (
    SELECT
        subject_id,
        hadm_id,
        COUNT(icd_code) AS diagnosis_count
    FROM cohort_diagnoses
    GROUP BY
        subject_id,
        hadm_id
)

SELECT
    'Cohort admissions' AS metric,
    COUNT(*)::numeric AS value
FROM cohort

UNION ALL

SELECT
    'Cohort admissions with at least one diagnosis',
    COUNT(*)::numeric
FROM diagnoses_per_cohort_admission
WHERE diagnosis_count > 0

UNION ALL

SELECT
    'Cohort admissions with seq_num = 1',
    COUNT(DISTINCT hadm_id)::numeric
FROM cohort_diagnoses
WHERE seq_num = 1

UNION ALL

SELECT
    'Total diagnosis rows linked to cohort',
    COUNT(icd_code)::numeric
FROM cohort_diagnoses

UNION ALL

SELECT
    'Minimum diagnoses per cohort admission',
    MIN(diagnosis_count)::numeric
FROM diagnoses_per_cohort_admission

UNION ALL

SELECT
    'Median diagnoses per cohort admission',
    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY diagnosis_count)::numeric
FROM diagnoses_per_cohort_admission

UNION ALL

SELECT
    'Mean diagnoses per cohort admission',
    ROUND(AVG(diagnosis_count)::numeric, 1)
FROM diagnoses_per_cohort_admission

UNION ALL

SELECT
    'Maximum diagnoses per cohort admission',
    MAX(diagnosis_count)::numeric
FROM diagnoses_per_cohort_admission

UNION ALL

SELECT
    'Rows produced by direct cohort-diagnosis join',
    COUNT(*)::numeric
FROM cohort_diagnoses

ORDER BY metric;
