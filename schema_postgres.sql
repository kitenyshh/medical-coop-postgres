-- СХЕМА БАЗЫ ДАННЫХ ДЛЯ ПРОЕКТА "МЕДИЦИНСКИЙ КООПЕРАТИВ" (PostgreSQL)


-- На всякий случай включаем расширение для UUID (пока не используем, но может пригодиться)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Очистка (для повторного запуска во время разработки)
DROP TABLE IF EXISTS prescriptions CASCADE;
DROP TABLE IF EXISTS visits CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP TABLE IF EXISTS diagnoses CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS doctors CASCADE;

-- ===== ТАБЛИЦЫ =====

-- Врачи
CREATE TABLE doctors (
    id          SERIAL PRIMARY KEY,
    login       VARCHAR(50) NOT NULL UNIQUE,
    password    VARCHAR(255) NOT NULL,
    full_name   VARCHAR(200) NOT NULL
);

-- Пациенты
CREATE TABLE patients (
    id            SERIAL PRIMARY KEY,
    full_name     VARCHAR(200) NOT NULL,
    gender        CHAR(1) NOT NULL CHECK (gender IN ('М', 'Ж')),
    birth_date    DATE,
    home_address  VARCHAR(255)
);

-- Справочник диагнозов
CREATE TABLE diagnoses (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(150) NOT NULL UNIQUE,
    description TEXT
);

-- Лекарства
CREATE TABLE medicines (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(150) NOT NULL UNIQUE,
    intake_method       VARCHAR(150),
    action_description  TEXT,
    side_effects        TEXT
);

-- Осмотры (визиты)
CREATE TABLE visits (
    id               SERIAL PRIMARY KEY,
    patient_id       INTEGER NOT NULL,
    doctor_id        INTEGER NOT NULL,
    visit_date       DATE NOT NULL,
    location         VARCHAR(50) NOT NULL, -- 'Приём' или 'На дому'
    symptoms         TEXT NOT NULL,
    diagnosis_id     INTEGER,
    prescription_text TEXT NOT NULL,

    CONSTRAINT fk_visits_patient
        FOREIGN KEY (patient_id)
        REFERENCES patients (id)
        ON DELETE CASCADE,

    CONSTRAINT fk_visits_doctor
        FOREIGN KEY (doctor_id)
        REFERENCES doctors (id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_visits_diagnosis
        FOREIGN KEY (diagnosis_id)
        REFERENCES diagnoses (id)
        ON DELETE SET NULL
);

-- Назначенные лекарства в рамках визита
CREATE TABLE prescriptions (
    id          SERIAL PRIMARY KEY,
    visit_id    INTEGER NOT NULL,
    medicine_id INTEGER NOT NULL,

    CONSTRAINT fk_prescriptions_visit
        FOREIGN KEY (visit_id)
        REFERENCES visits (id)
        ON DELETE CASCADE,

    CONSTRAINT fk_prescriptions_medicine
        FOREIGN KEY (medicine_id)
        REFERENCES medicines (id)
        ON DELETE RESTRICT
);

-- ===== НАЧАЛЬНЫЕ ДАННЫЕ ДЛЯ ТЕСТА =====

-- Врачи
INSERT INTO doctors (login, password, full_name) VALUES
('doctor1', 'doctor123', 'Печорин Григорий Александрович'),
('doctor2', 'doctor123', 'Грушницкий Скрытич Скрытный');

-- Пациенты
INSERT INTO patients (full_name, gender, birth_date, home_address) VALUES
('Бесфамильный Максим Максимыч', 'М', '1975-02-18', 'г. Москва, ул. Семеновская наб, д. 2/1 с2'),
('Черкесская Бэла Батьковна',   'Ж', '2009-02-19', 'г. Москва, ул. Гольяновский вал, д. 16/2');

-- Диагнозы
INSERT INTO diagnoses (name, description) VALUES
('Грипп', 'Острое респираторное вирусное заболевание'),
('ОРВИ',  'Острое респираторное вирусное заболевание верхних дыхательных путей');

-- Лекарства
INSERT INTO medicines (name, intake_method, action_description, side_effects) VALUES
('Парацетамол', '1 табл. 3 раза в день', 'Жаропонижающее и болеутоляющее средство', 'Тошнота, аллергические реакции'),
('Аспирин',     '1 табл. 2 раза в день', 'Противовоспалительное средство', 'Раздражение желудка, кровоточивость');

-- Пара примерных визитов
INSERT INTO visits (patient_id, doctor_id, visit_date, location, symptoms, diagnosis_id, prescription_text) VALUES
(1, 1, CURRENT_DATE, 'Приём', 'Повышенная температура, кашель', 1, 'Постельный режим, обильное питьё'),
(2, 2, CURRENT_DATE, 'На дому', 'Насморк, боль в горле', 2, 'Больше жидкости, тёплое питьё');

-- Привязка лекарств к визитам
INSERT INTO prescriptions (visit_id, medicine_id) VALUES
(1, 1),
(1, 2),
(2, 1);
