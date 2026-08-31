-- Adult First ICU Stay Cohort
-- Candidate laboratory coverage
--
-- Purpose:
-- Measure availability of selected common laboratory tests during the first
-- 24 hours of the index ICU stay before designing the final lab dataset.
--
-- Only numeric laboratory results linked to the index hospital admission are
-- included.
--
-- Note:
-- Explicit casts are temporarily required because charttime is currently
-- stored as text and labevents.hadm_id is currently stored as double
-- precision in PostgreSQL.

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
        stay_id,
        icu_intime
    FROM ranked_stays
    WHERE patient_stay_number = 1
),

candidate_labs AS (
    SELECT *
    FROM (
        VALUES
            (50912, 'Creatinine'),
            (50931, 'Glucose'),
            (50971, 'Potassium'),
            (50983, 'Sodium'),
            (50882, 'Bicarbonate'),
            (51006, 'Urea Nitrogen'),
            (51222, 'Hemoglobin'),
            (51301, 'White Blood Cells'),
            (51265, 'Platelet Count')
    ) AS labs (
        itemid,
        lab_name
    )
),

cohort_lab_measurements AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.icu_intime,
        labs.itemid,
        labs.lab_name,
        l.labevent_id,
        l.charttime::timestamp AS charttime,
        l.valuenum,
        l.valueuom
    FROM cohort AS c
    CROSS JOIN candidate_labs AS labs
    LEFT JOIN hosp.labevents AS l
        ON c.subject_id = l.subject_id
        AND c.hadm_id = l.hadm_id::bigint
        AND labs.itemid = l.itemid
        AND l.valuenum IS NOT NULL
        AND l.charttime::timestamp >= c.icu_intime
        AND l.charttime::timestamp < (
            c.icu_intime + INTERVAL '24 hours'
        )
),

lab_coverage AS (
    SELECT
        itemid,
        lab_name,
        COUNT(DISTINCT subject_id) FILTER (
            WHERE labevent_id IS NOT NULL
        ) AS patients_with_measurement,
        COUNT(labevent_id) AS measurement_count
    FROM cohort_lab_measurements
    GROUP BY
        itemid,
        lab_name
)

SELECT
    itemid,
    lab_name,
    patients_with_measurement,
    88 - patients_with_measurement AS patients_without_measurement,
    ROUND(
        (
            100.0 * patients_with_measurement / 88
        )::numeric,
        1
    ) AS patient_coverage_pct,
    measurement_count,
    ROUND(
        (
            measurement_count::numeric
            / NULLIF(patients_with_measurement, 0)
        ),
        1
    ) AS measurements_per_measured_patient
FROM lab_coverage
ORDER BY
    patient_coverage_pct DESC,
    lab_name;
