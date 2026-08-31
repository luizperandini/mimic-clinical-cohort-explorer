-- Adult First ICU Stay Cohort
-- First-24-hour laboratory dataset
--
-- Grain:
-- One row per numeric measurement for a selected laboratory test occurring
-- during the first 24 hours of the patient's index ICU stay.
--
-- The parent cohort remains one row per patient.
--
-- Observation window:
-- ICU admission time <= laboratory chart time < ICU admission time + 24 hours
--
-- Note:
-- Explicit casts are temporarily required because charttime is stored as
-- text and labevents.hadm_id is stored as double precision in the current
-- PostgreSQL database.

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
        stay_id,
        icu_intime
    FROM ranked_stays
    WHERE patient_stay_number = 1
),

candidate_labs AS (
    SELECT *
    FROM (
        VALUES
            (50882, 'Bicarbonate'),
            (50912, 'Creatinine'),
            (50931, 'Glucose'),
            (51222, 'Hemoglobin'),
            (51265, 'Platelet Count'),
            (50971, 'Potassium'),
            (50983, 'Sodium'),
            (51006, 'Urea Nitrogen'),
            (51301, 'White Blood Cells')
    ) AS labs (
        itemid,
        lab_name
    )
)

SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    l.labevent_id,
    l.itemid,
    labs.lab_name,
    l.charttime::timestamp AS lab_charttime,
    EXTRACT(
        EPOCH FROM (
            l.charttime::timestamp - c.icu_intime
        )
    ) / 3600.0 AS hours_from_icu_admit,
    l.valuenum AS lab_value,
    l.valueuom AS lab_unit,
    l.flag AS lab_flag
FROM cohort AS c
INNER JOIN hosp.labevents AS l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id::bigint
INNER JOIN candidate_labs AS labs
    ON l.itemid = labs.itemid
WHERE
    l.valuenum IS NOT NULL
    AND l.charttime::timestamp >= c.icu_intime
    AND l.charttime::timestamp < (
        c.icu_intime + INTERVAL '24 hours'
    )
ORDER BY
    c.subject_id,
    c.hadm_id,
    l.charttime::timestamp,
    l.labevent_id;
