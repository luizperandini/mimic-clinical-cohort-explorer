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
-- Note:
-- Explicit timestamp casts are temporarily required because several source
-- date-time columns are currently stored as text in PostgreSQL.

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
)

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
ORDER BY subject_id;
