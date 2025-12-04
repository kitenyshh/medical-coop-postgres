-- ПАКЕТ coop_api: функции, процедуры и триггеры для проекта "Медицинский кооператив"

-- Выполнять внутри базы medical_coop

-- Создаём отдельную схему-пакет
CREATE SCHEMA IF NOT EXISTS coop_api;
SET search_path TO coop_api, public;

-- =========================
-- 1. ФУНКЦИИ ДЛЯ ОТЧЁТОВ
-- =========================

-- 1.1. Вызовы по дате: дата, кол-во визитов, врачи
CREATE OR REPLACE FUNCTION get_visits_by_date(p_date date)
RETURNS TABLE (
    visit_date date,
    visits_count integer,
    doctors_list text
)
LANGUAGE sql
AS $$
    SELECT
        v.visit_date,
        COUNT(*) AS visits_count,
        STRING_AGG(DISTINCT d.full_name, ', ') AS doctors_list
    FROM visits v
    JOIN doctors d ON d.id = v.doctor_id
    WHERE v.visit_date = p_date
    GROUP BY v.visit_date
    ORDER BY v.visit_date;
$$;

-- 1.2. Количество пациентов по диагнозу
CREATE OR REPLACE FUNCTION get_patients_by_diagnosis()
RETURNS TABLE (
    diagnosis_name text,
    patients_count integer
)
LANGUAGE sql
AS $$
    SELECT
        dg.name AS diagnosis_name,
        COUNT(DISTINCT v.patient_id) AS patients_count
    FROM visits v
    JOIN diagnoses dg ON dg.id = v.diagnosis_id
    GROUP BY dg.name
    ORDER BY dg.name;
$$;

-- 1.3. Лекарства и побочные эффекты
CREATE OR REPLACE FUNCTION get_medicine_effects()
RETURNS TABLE (
    medicine_name text,
    intake_method text,
    action_description text,
    side_effects text
)
LANGUAGE sql
AS $$
    SELECT
        m.name,
        m.intake_method,
        m.action_description,
        m.side_effects
    FROM medicines m
    ORDER BY m.name;
$$;

-- =========================
-- 2. ПРОЦЕДУРЫ
-- =========================

-- 2.1. Добавление нового лекарства
CREATE OR REPLACE PROCEDURE add_medicine(
    IN p_name text,
    IN p_intake_method text,
    IN p_action_description text,
    IN p_side_effects text
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO medicines (name, intake_method, action_description, side_effects)
    VALUES (p_name, p_intake_method, p_action_description, p_side_effects);
END;
$$;

-- 2.2. Добавление визита и назначения существующего лекарства
CREATE OR REPLACE PROCEDURE add_visit_with_prescription(
    IN p_patient_id integer,
    IN p_doctor_id integer,
    IN p_visit_date date,
    IN p_location text,
    IN p_symptoms text,
    IN p_diagnosis_id integer,
    IN p_prescription_text text,
    IN p_medicine_id integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_visit_id integer;
BEGIN
    INSERT INTO visits (
        patient_id, doctor_id, visit_date, location,
        symptoms, diagnosis_id, prescription_text
    )
    VALUES (
        p_patient_id, p_doctor_id, p_visit_date, p_location,
        p_symptoms, p_diagnosis_id, p_prescription_text
    )
    RETURNING id INTO v_visit_id;

    IF p_medicine_id IS NOT NULL THEN
        INSERT INTO prescriptions (visit_id, medicine_id)
        VALUES (v_visit_id, p_medicine_id);
    END IF;
END;
$$;

-- 2.3. Добавление визита и одновременно нового лекарства
CREATE OR REPLACE PROCEDURE add_visit_with_new_medicine(
    IN p_patient_id integer,
    IN p_doctor_id integer,
    IN p_visit_date date,
    IN p_location text,
    IN p_symptoms text,
    IN p_diagnosis_id integer,
    IN p_prescription_text text,
    IN p_med_name text,
    IN p_med_intake_method text,
    IN p_med_action_description text,
    IN p_med_side_effects text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_visit_id integer;
    v_medicine_id integer;
BEGIN
    INSERT INTO visits (
        patient_id, doctor_id, visit_date, location,
        symptoms, diagnosis_id, prescription_text
    )
    VALUES (
        p_patient_id, p_doctor_id, p_visit_date, p_location,
        p_symptoms, p_diagnosis_id, p_prescription_text
    )
    RETURNING id INTO v_visit_id;

    INSERT INTO medicines (name, intake_method, action_description, side_effects)
    VALUES (p_med_name, p_med_intake_method, p_med_action_description, p_med_side_effects)
    RETURNING id INTO v_medicine_id;

    INSERT INTO prescriptions (visit_id, medicine_id)
    VALUES (v_visit_id, v_medicine_id);
END;
$$;

-- =========================
-- 3. ТРИГГЕРЫ КАСКАДНЫХ ИЗМЕНЕНИЙ
-- =========================

-- 3.1. Каскадное удаление данных пациента (визиты + назначения)
CREATE OR REPLACE FUNCTION trg_delete_patient_cascade_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Удаляем назначения по визитам пациента
    DELETE FROM prescriptions
    WHERE visit_id IN (
        SELECT id FROM visits WHERE patient_id = OLD.id
    );

    -- Удаляем визиты пациента
    DELETE FROM visits
    WHERE patient_id = OLD.id;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_delete_patient_cascade ON patients;

CREATE TRIGGER trg_delete_patient_cascade
BEFORE DELETE ON patients
FOR EACH ROW
EXECUTE FUNCTION trg_delete_patient_cascade_fn();

-- 3.2. Очистка назначений при удалении лекарства
CREATE OR REPLACE FUNCTION trg_delete_medicine_cleanup_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM prescriptions
    WHERE medicine_id = OLD.id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_delete_medicine_cleanup ON medicines;

CREATE TRIGGER trg_delete_medicine_cleanup
BEFORE DELETE ON medicines
FOR EACH ROW
EXECUTE FUNCTION trg_delete_medicine_cleanup_fn();
