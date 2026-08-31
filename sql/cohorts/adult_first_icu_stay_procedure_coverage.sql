-- Adult First ICU Stay Cohort
-- Procedure coverage within the final cohort
--
-- Purpose:
-- Measure procedure availability and row expansion specifically for the
-- 88 index hospital admissions selected by the cohort.

\pset pager off

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
),

cohort AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id
    FROM ranked_stays
    WHERE patient_stay_number = 1
),

cohort_procedures AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        p.seq_num,
        p.chartdate,
        p.icd_code,
        p.icd_version,
        d.long_title
    FROM cohort AS c
    LEFT JOIN hosp.procedures_icd AS p
        ON c.subject_id = p.subject_id
        AND c.hadm_id = p.hadm_id
    LEFT JOIN hosp.d_icd_procedures AS d
        ON p.icd_code = d.icd_code
        AND p.icd_version = d.icd_version
),

procedures_per_cohort_admission AS (
    SELECT
        subject_id,
        hadm_id,
        COUNT(icd_code) AS procedure_count
    FROM cohort_procedures
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
    'Cohort admissions with at least one procedure',
    COUNT(*)::numeric
FROM procedures_per_cohort_admission
WHERE procedure_count > 0

UNION ALL

SELECT
    'Cohort admissions without procedures',
    COUNT(*)::numeric
FROM procedures_per_cohort_admission
WHERE procedure_count = 0

UNION ALL

SELECT
    'Cohort admissions with seq_num = 1',
    COUNT(DISTINCT hadm_id)::numeric
FROM cohort_procedures
WHERE seq_num = 1

UNION ALL

SELECT
    'Total procedure rows linked to cohort',
    COUNT(icd_code)::numeric
FROM cohort_procedures

UNION ALL

SELECT
    'Minimum procedures among admissions with procedures',
    MIN(procedure_count)::numeric
FROM procedures_per_cohort_admission
WHERE procedure_count > 0

UNION ALL

SELECT
    'Median procedures among admissions with procedures',
    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY procedure_count)::numeric
FROM procedures_per_cohort_admission
WHERE procedure_count > 0

UNION ALL

SELECT
    'Mean procedures among admissions with procedures',
    ROUND(AVG(procedure_count)::numeric, 1)
FROM procedures_per_cohort_admission
WHERE procedure_count > 0

UNION ALL

SELECT
    'Maximum procedures among admissions with procedures',
    MAX(procedure_count)::numeric
FROM procedures_per_cohort_admission
WHERE procedure_count > 0

UNION ALL

SELECT
    'Rows produced by LEFT cohort-procedure join',
    COUNT(*)::numeric
FROM cohort_procedures

ORDER BY metric;
