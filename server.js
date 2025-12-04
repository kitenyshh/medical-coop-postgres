const express = require('express');
const path = require('path');
const { Pool } = require('pg');

const app = express();
const port = 3000;

// Подключение к PostgreSQL
const pool = new Pool({
  host: 'localhost',
  port: 5433,                // твой порт PostgreSQL
  user: 'postgres',          // при необходимости поменяй
  password: 'bamipo32',     // твой пароль
  database: 'medical_coop',
});

// Проверка подключения
pool.connect()
  .then(client => {
    console.log('✅ Подключение к PostgreSQL успешно');
    client.release();
  })
  .catch(err => {
    console.error('❌ Ошибка подключения к PostgreSQL:', err);
  });

// Настройки Express
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Простая "сессия"
let currentUser = null;

// ======================
// ГЛАВНАЯ
// ======================

app.get('/', (req, res) => {
  res.render('home', { doctor: currentUser });
});

// ======================
// АВТОРИЗАЦИЯ / РЕГИСТРАЦИЯ
// ======================

app.get('/login', (req, res) => {
  res.render('login', { error: null });
});

app.post('/login', async (req, res) => {
  const { login, password } = req.body;

  try {
    const result = await pool.query(
      'SELECT * FROM doctors WHERE login = $1',
      [login]
    );

    const doctor = result.rows[0];

    if (!doctor || doctor.password !== password) {
      return res.render('login', { error: 'Неверный логин или пароль' });
    }

    currentUser = doctor;
    res.redirect('/exam');
  } catch (err) {
    console.error(err);
    res.render('login', { error: 'Ошибка БД' });
  }
});

app.get('/register', (req, res) => {
  res.render('register', { error: null });
});

app.post('/register', async (req, res) => {
  const { login, password, full_name } = req.body;

  if (!login || !password || !full_name) {
    return res.render('register', { error: 'Заполните все поля' });
  }

  try {
    await pool.query(
      'INSERT INTO doctors (login, password, full_name) VALUES ($1, $2, $3)',
      [login, password, full_name]
    );
    res.redirect('/login');
  } catch (err) {
    console.error(err);
    res.render('register', { error: 'Такой логин уже существует' });
  }
});

app.get('/logout', (req, res) => {
  currentUser = null;
  res.redirect('/');
});

// ======================
// ПАЦИЕНТЫ
// ======================

app.get('/patients', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  try {
    const result = await pool.query(
      'SELECT * FROM patients ORDER BY id'
    );
    res.render('patients_list', {
      doctor: currentUser,
      patients: result.rows,
    });
  } catch (err) {
    console.error(err);
    res.send('Ошибка БД при загрузке списка пациентов');
  }
});

app.get('/patients/new', (req, res) => {
  if (!currentUser) return res.redirect('/login');
  res.render('patient_new', { doctor: currentUser, error: null });
});

app.post('/patients/new', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  const { full_name, gender, birth_date, home_address } = req.body;

  if (!full_name || !gender) {
    return res.render('patient_new', {
      doctor: currentUser,
      error: 'Имя и пол обязательны',
    });
  }

  try {
    await pool.query(
      'INSERT INTO patients (full_name, gender, birth_date, home_address) VALUES ($1, $2, $3, $4)',
      [full_name, gender, birth_date || null, home_address || null]
    );
    res.redirect('/patients');
  } catch (err) {
    console.error(err);
    res.render('patient_new', {
      doctor: currentUser,
      error: 'Ошибка добавления пациента',
    });
  }
});

app.get('/patients/:id', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  const patientId = req.params.id;

  try {
    const patientRes = await pool.query(
      'SELECT * FROM patients WHERE id = $1',
      [patientId]
    );
    const patient = patientRes.rows[0];
    if (!patient) return res.send('Пациент не найден');

    const visitsRes = await pool.query(
      `
      SELECT
        v.id,
        v.visit_date,
        v.location,
        v.symptoms,
        v.prescription_text,
        d.name AS diagnosis_name,
        STRING_AGG(DISTINCT m.name, ', ') AS medicines
      FROM visits v
      LEFT JOIN diagnoses d ON d.id = v.diagnosis_id
      LEFT JOIN prescriptions pr ON pr.visit_id = v.id
      LEFT JOIN medicines m ON m.id = pr.medicine_id
      WHERE v.patient_id = $1
      GROUP BY v.id, v.visit_date, v.location, v.symptoms, v.prescription_text, d.name
      ORDER BY v.visit_date DESC
      `,
      [patientId]
    );

    const diagnosesRes = await pool.query(
      'SELECT * FROM diagnoses ORDER BY id'
    );

    res.render('patient_card', {
      doctor: currentUser,
      patient,
      visits: visitsRes.rows,
      diagnoses: diagnosesRes.rows,
    });
  } catch (err) {
    console.error(err);
    res.send('Ошибка БД при загрузке карточки пациента');
  }
});

app.post('/patients/:id/add-diagnosis', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  const patientId = req.params.id;
  const {
    visit_date,
    location,
    symptoms,
    diagnosis_id,
    prescription_text,
  } = req.body;

  const dateValue = visit_date || new Date().toISOString().slice(0, 10);
  const locValue = location || 'Приём';

  try {
    await pool.query(
      `
      INSERT INTO visits
        (patient_id, doctor_id, visit_date, location, symptoms, diagnosis_id, prescription_text)
      VALUES
        ($1, $2, $3, $4, $5, $6, $7)
      `,
      [
        patientId,
        currentUser.id,
        dateValue,
        locValue,
        symptoms,
        diagnosis_id || null,
        prescription_text,
      ]
    );

    res.redirect(`/patients/${patientId}`);
  } catch (err) {
    console.error(err);
    res.send('Ошибка добавления диагноза для пациента');
  }
});

// ======================
// ДИАГНОЗЫ
// ======================

app.get('/diagnoses', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  try {
    const result = await pool.query(
      'SELECT * FROM diagnoses ORDER BY id'
    );
    res.render('diagnoses', {
      doctor: currentUser,
      diagnoses: result.rows,
      error: null,
    });
  } catch (err) {
    console.error(err);
    res.send('Ошибка БД при загрузке диагнозов');
  }
});

app.post('/diagnoses', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  const { name, description } = req.body;

  if (!name) {
    const result = await pool.query('SELECT * FROM diagnoses ORDER BY id');
    return res.render('diagnoses', {
      doctor: currentUser,
      diagnoses: result.rows,
      error: 'Название диагноза обязательно',
    });
  }

  try {
    await pool.query(
      'INSERT INTO diagnoses (name, description) VALUES ($1, $2)',
      [name, description || null]
    );
    res.redirect('/diagnoses');
  } catch (err) {
    console.error(err);
    const result = await pool.query('SELECT * FROM diagnoses ORDER BY id');
    res.render('diagnoses', {
      doctor: currentUser,
      diagnoses: result.rows,
      error: 'Такой диагноз уже существует',
    });
  }
});

// ======================
// ОСМОТРЫ
// ======================

app.get('/exam', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  try {
    const patientsRes = await pool.query('SELECT * FROM patients ORDER BY id');
    const diagnosesRes = await pool.query('SELECT * FROM diagnoses ORDER BY id');
    const medsRes = await pool.query('SELECT * FROM medicines ORDER BY id');

    res.render('exam', {
      doctor: currentUser,
      patients: patientsRes.rows,
      diagnoses: diagnosesRes.rows,
      medicines: medsRes.rows,
    });
  } catch (err) {
    console.error(err);
    res.send('Ошибка БД при загрузке осмотра');
  }
});

app.post('/exam', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  const {
    patient_id,
    visit_date,
    location,
    symptoms,
    diagnosis_id,
    prescription_text,
    existing_medicine_id,
    new_med_name,
    new_med_intake_method,
    new_med_action_description,
    new_med_side_effects,
  } = req.body;

  const dateValue = visit_date || new Date().toISOString().slice(0, 10);

  try {
    if (new_med_name) {
      await pool.query(
        `
        CALL coop_api.add_visit_with_new_medicine(
          $1, $2, $3, $4, $5, $6, $7,
          $8, $9, $10, $11
        )
        `,
        [
          patient_id,
          currentUser.id,
          dateValue,
          location,
          symptoms,
          diagnosis_id || null,
          prescription_text,
          new_med_name,
          new_med_intake_method || null,
          new_med_action_description || null,
          new_med_side_effects || null,
        ]
      );
    } else {
      await pool.query(
        'CALL coop_api.add_visit_with_prescription($1, $2, $3, $4, $5, $6, $7, $8)',
        [
          patient_id,
          currentUser.id,
          dateValue,
          location,
          symptoms,
          diagnosis_id || null,
          prescription_text,
          existing_medicine_id || null,
        ]
      );
    }

    res.redirect('/exam');
  } catch (err) {
    console.error(err);
    res.send('Ошибка сохранения осмотра');
  }
});

// ======================
// ОТЧЁТЫ
// ======================

app.get('/reports', async (req, res) => {
  if (!currentUser) return res.redirect('/login');

  const date = req.query.date || new Date().toISOString().slice(0, 10);

  try {
    const visitsByDateRes = await pool.query(
      'SELECT * FROM coop_api.get_visits_by_date($1)',
      [date]
    );
    const byDiagRes = await pool.query(
      'SELECT * FROM coop_api.get_patients_by_diagnosis()'
    );
    const medsRes = await pool.query(
      'SELECT * FROM coop_api.get_medicine_effects()'
    );

    res.render('reports', {
      doctor: currentUser,
      date,
      visitsByDate: visitsByDateRes.rows,
      byDiagnosis: byDiagRes.rows,
      medicines: medsRes.rows,
    });
  } catch (err) {
    console.error(err);
    res.send('Ошибка БД при формировании отчётов');
  }
});

// ======================
// ЗАПУСК СЕРВЕРА
// ======================

app.listen(port, () => {
  console.log(`🚀 Сервер запущен: http://localhost:${port}`);
});
