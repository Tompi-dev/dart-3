# 🧠 AITU Nomad Project — Backend (Dart + PostgreSQL + JWT)

## 🚀 Overview
This backend project implements a simple learning management system built with **Dart**, **Shelf**, and **PostgreSQL**.  
It supports:
- User registration and login with JWT authorization
- Role-based access (Admin / Teacher / Student)
- Group creation and student enrollment (normal and trial)
- Time conflict validation and data logging

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
Копировать код
CREATE DATABASE nomad_project;
\c nomad_project;
Create Tables
sql
Копировать код
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name TEXT,
  email TEXT UNIQUE,
  password TEXT,
  role TEXT CHECK (role IN ('student','teacher','admin'))
);

CREATE TABLE teachers (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id)
);

CREATE TABLE students (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id)
);

CREATE TABLE halls (
  id SERIAL PRIMARY KEY,
  name TEXT
);

CREATE TABLE groups (
  id SERIAL PRIMARY KEY,
  name TEXT,
  teacher_id INT REFERENCES teachers(id),
  hall_id INT REFERENCES halls(id),
  start_time TIMESTAMP,
  end_time TIMESTAMP
);

CREATE TABLE group_students (
  id SERIAL PRIMARY KEY,
  group_id INT REFERENCES groups(id),
  student_id INT REFERENCES students(id),
  is_trial BOOLEAN DEFAULT FALSE
);


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
