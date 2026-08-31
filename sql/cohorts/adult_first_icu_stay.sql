-- Adult First ICU Stay Cohort
--
-- Grain:
-- One row per patient, representing the patient's earliest eligible ICU stay.
--
-- Eligibility:
-- 1. Valid patient and hospital-admission relationships.
-- 2. Valid ICU admission and discharge timestamps.
-- 3. Age at hospital admission greater than or equal to 18 years.
-- 4. ICU length of stay greater than or equal to 1.0 day.
--
-- Diagnosis enrichment:
-- Diagnosis records are aggregated to one row per hospital admission before
-- being joined to the cohort. This preserves the one-row-per-patient grain.
--
-- Procedure enrichment:
-- Procedure records are aggregated to one row per hospital admission before
-- being joined to the cohort. Admissions without recorded ICD procedures
-- remain in the cohort with has_procedure = 0 and procedure_count = 0.
--
-- Note:
-- Explicit timestamp/date casts are temporarily required because several
-- source date-time columns are currently stored as text in PostgreSQL.

WITH source_icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.first_careunit,
        i.last_careunit,
        i.intime::timestamp AS icu_intime,
        i.outtime::timestamp AS icu_outtime,
        i.los::double precision AS icu_los_days
    FROM icu.icustays AS i
),

linked_admissions AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.first_careunit,
        i.last_careunit,
        i.icu_intime,
        i.icu_outtime,
        i.icu_los_days,
        a.admittime::timestamp AS hospital_admittime,
        a.dischtime::timestamp AS hospital_dischtime,
        a.admission_type,
        a.race,
        a.insurance,
        a.marital_status,
        a.hospital_expire_flag
    FROM source_icu_stays AS i
    INNER JOIN hosp.admissions AS a
        ON i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
),

linked_patients AS (
    SELECT
        a.*,
        p.gender,
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
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        gender,
        age_at_admission,
        admission_type,
        race,
        insurance,
        marital_status,
        hospital_expire_flag,
        hospital_admittime,
        hospital_dischtime,
        EXTRACT(
            EPOCH FROM (
                hospital_dischtime - hospital_admittime
            )
        ) / 86400.0 AS hospital_los_days,
        icu_intime,
        icu_outtime,
        icu_los_days,
        first_careunit,
        last_careunit
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

final_cohort AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        gender,
        age_at_admission,
        admission_type,
        race,
        insurance,
        marital_status,
        hospital_expire_flag,
        hospital_admittime,
        hospital_dischtime,
        hospital_los_days,
        icu_intime,
        icu_outtime,
        icu_los_days,
        first_careunit,
        last_careunit
    FROM ranked_eligible_stays
    WHERE patient_stay_number = 1
),

diagnosis_summary AS (
    SELECT
        dx.subject_id,
        dx.hadm_id,
        COUNT(*) AS diagnosis_count,
        MAX(dx.icd_code) FILTER (
            WHERE dx.seq_num = 1
        ) AS priority_1_icd_code,
        MAX(dx.icd_version) FILTER (
            WHERE dx.seq_num = 1
        ) AS priority_1_icd_version,
        MAX(d.long_title) FILTER (
            WHERE dx.seq_num = 1
        ) AS priority_1_diagnosis_title
    FROM hosp.diagnoses_icd AS dx
    LEFT JOIN hosp.d_icd_diagnoses AS d
        ON dx.icd_code = d.icd_code
        AND dx.icd_version = d.icd_version
    GROUP BY
        dx.subject_id,
        dx.hadm_id
),

procedure_summary AS (
    SELECT
        p.subject_id,
        p.hadm_id,
        COUNT(*) AS procedure_count
    FROM hosp.procedures_icd AS p
    GROUP BY
        p.subject_id,
        p.hadm_id
)

SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.gender,
    c.age_at_admission,
    c.admission_type,
    c.race,
    c.insurance,
    c.marital_status,
    c.hospital_expire_flag,
    c.hospital_admittime,
    c.hospital_dischtime,
    c.hospital_los_days,
    c.icu_intime,
    c.icu_outtime,
    c.icu_los_days,
    c.first_careunit,
    c.last_careunit,
    d.diagnosis_count,
    d.priority_1_icd_code,
    d.priority_1_icd_version,
    d.priority_1_diagnosis_title,
    CASE
        WHEN p.procedure_count IS NULL THEN 0
        ELSE 1
    END AS has_procedure,
    COALESCE(
        p.procedure_count,
        0
    ) AS procedure_count
FROM final_cohort AS c
LEFT JOIN diagnosis_summary AS d
    ON c.subject_id = d.subject_id
    AND c.hadm_id = d.hadm_id
LEFT JOIN procedure_summary AS p
    ON c.subject_id = p.subject_id
    AND c.hadm_id = p.hadm_id
ORDER BY c.subject_id;