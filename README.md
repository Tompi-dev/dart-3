# 🧠 AITU Nomad Project — Backend (Dart + PostgreSQL + JWT)

## 🚀 Overview
This backend project implements a simple learning management system built with **Dart**, **Shelf**, and **PostgreSQL**.  
It supports:
- User registration and login with JWT authorization
- Role-based access (Admin / Teacher / Student)
- Group creation and student enrollment (normal and trial)
- Time conflict validation and data logging

BTW drugoi.dart - is middleware for jwt tokenization
---

## 🧩 Tech Stack
| Component | Description |
|------------|-------------|
| **Language** | Dart 3.x |
| **Framework** | Shelf (REST API) |
| **Database** | PostgreSQL |
| **Auth** | JWT (dart_jsonwebtoken) |
| **Config** | dotenv |
| **ORM/SQL** | `package:postgres` with `Sql.named` queries |

---

## ⚙️ 1. Project Setup

### 📦 Requirements
- Dart SDK ≥ 3.0  
- PostgreSQL ≥ 15  
- Git  
- (Optional) Postman for testing

### 📂 Clone & Install
```bash
git clone https://github.com/<your-username>/nomad-backend.git
cd nomad-backend

## Install dependencies
dart pub add shelf shelf_router postgres dart_jsonwebtoken dotenv
dart pub get



##  2. Database Setup (PostgreSQL)
Create Database
sql

-- USERS
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
  contact_info TEXT
);

-- TEACHERS
CREATE TABLE teachers (
  id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  work_hours JSONB DEFAULT '{}'::jsonb,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'sick', 'leave'))
);

-- STUDENTS
CREATE TABLE students (
  id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  is_trial BOOLEAN DEFAULT FALSE
);

-- HALLS
CREATE TABLE halls (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  capacity INT DEFAULT NULL
);

-- GROUPS
CREATE TABLE groups (
  id SERIAL PRIMARY KEY,
  teacher_id INT REFERENCES teachers(id) ON DELETE SET NULL,
  hall_id INT REFERENCES halls(id) ON DELETE SET NULL,
  start_time TIMESTAMPTZ NOT NULL,
  duration INTERVAL DEFAULT INTERVAL '90 minutes',
  is_additional BOOLEAN DEFAULT FALSE
);

-- GROUP_STUDENTS
CREATE TABLE group_students (
  group_id INT REFERENCES groups(id) ON DELETE CASCADE,
  student_id INT REFERENCES students(id) ON DELETE CASCADE,
  is_trial BOOLEAN DEFAULT FALSE,
  PRIMARY KEY (group_id, student_id)
);

-- SCHEDULE_EXCEPTIONS
CREATE TABLE schedule_exceptions (
  id SERIAL PRIMARY KEY,
  teacher_id INT REFERENCES teachers(id) ON DELETE CASCADE,
  hall_id INT REFERENCES halls(id) ON DELETE SET NULL,
  group_id INT REFERENCES groups(id) ON DELETE SET NULL,
  exception_type TEXT CHECK (exception_type IN ('overlap', 'move', 'cancel')),
  approved_by_admin BOOLEAN DEFAULT FALSE,
  new_time TIMESTAMPTZ
);

CREATE TABLE logs (
  id SERIAL PRIMARY KEY,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE users               ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE teachers            ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(), ADD COLUMN created_by INT REFERENCES users(id);
ALTER TABLE students            ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(), ADD COLUMN created_by INT REFERENCES users(id);
ALTER TABLE halls               ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(), ADD COLUMN created_by INT REFERENCES users(id);
ALTER TABLE groups              ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(), ADD COLUMN created_by INT REFERENCES users(id);
ALTER TABLE group_students      ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(), ADD COLUMN created_by INT REFERENCES users(id);
ALTER TABLE schedule_exceptions ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(), ADD COLUMN created_by INT REFERENCES users(id);

ALTER TABLE groups ADD COLUMN cancelled BOOLEAN DEFAULT FALSE;

ALTER TABLE teachers
ADD COLUMN is_frozen BOOLEAN DEFAULT FALSE;






## 3. Environment Configuration
Create a .env file in the root directory:


DB_HOST=localhost
DB_PORT=5432
DB_NAME=nomad_project
DB_USER=postgres
DB_PASSWORD=yourpassword


## 4. Run the Server

dart run lib/server.dart
✅ Output example:


✅ Server running on http://localhost:8080


Max Planck Institute for Informatics (Saarbruecken)
has Departments
D1
Algorithms and Complexity
Prof. Danupon Nanongkai, Ph.D.
D2
Computer Vision and Machine Learning
Prof. Dr. Bernt Schiele
D3
Internet Architecture
Prof. Anja Feldmann, Ph.D.
D4
Computer Graphics
Prof. Dr. Hans-Peter Seidel
D5
Databases and Information Systems
Prof. Dr. Gerhard Weikum
D6
Visual Computing and Artificial Intelligence
Prof. Dr. Christian Theobalt
RG1
Automation of Logic
Prof. Dr. Christoph Weidenbach
RG2
Network and Cloud Systems
Dr. Yiting Xia
RG3
Multimodal Language Processing
Prof. Dr. Vera Demberg

 
Max Planck Institute for Software Systems (Kaiserslautern and Saarbruecken)
hasResearch areas

Algorithms, Theory & Logic

Computer Systems

Cyber-Physical Systems

Programming Languages & Verification

Social & Information Systems

More CS @ Max Planck

 
Max Planck Institute for Security and Privacy (Bochum)

which i should apply if:

