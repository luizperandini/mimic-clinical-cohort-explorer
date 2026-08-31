-- Adult First ICU Stay Cohort
-- Long-form procedure dataset
--
-- Grain:
-- One row per ICD procedure associated with the index hospital admission
-- represented in the Adult First ICU Stay Cohort.
--
-- Only admissions with recorded procedures appear in this child dataset.
-- Admissions without procedures remain represented in the parent cohort.
--
-- Note:
-- chartdate is temporarily cast from text to date because the current ETL
-- loader imported date fields as text.

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

ranked_eligible_stays AS (
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
    FROM ranked_eligible_stays
    WHERE patient_stay_number = 1
)

SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    p.seq_num AS procedure_priority,
    p.chartdate::date AS procedure_date,
    p.icd_code,
    p.icd_version,
    d.long_title AS procedure_title
FROM cohort AS c
INNER JOIN hosp.procedures_icd AS p
    ON c.subject_id = p.subject_id
    AND c.hadm_id = p.hadm_id
INNER JOIN hosp.d_icd_procedures AS d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
ORDER BY
    c.subject_id,
    c.hadm_id,
    p.seq_num,
    p.chartdate::date,
    p.icd_code;
