# Offline LAN-Based Mobile Attendance Management System
## Complete Setup Guide

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET (Online Sync)                    │
│                                                             │
│           ┌─────────────────────────┐                      │
│           │   Spring Boot Server    │                      │
│           │   (Central MySQL DB)    │                      │
│           └──────────┬──────────────┘                      │
└──────────────────────┼──────────────────────────────────────┘
                       │ JWT API (sync only)
═══════════════════════╪══════════════════════════════════════
                  LOCAL LAN (Offline)
                       │
        ┌──────────────┼───────────────┐
        │              │               │
   ┌────▼────┐   ┌─────▼──────┐  ┌────▼────┐
   │ Teacher │   │  Teacher   │  │ Student │
   │  App    │──▶│ LAN Server │◀─│   App  │
   │(Flutter)│   │ :8181      │  │(Flutter)│
   │ SQLite  │   └────────────┘  └─────────┘
   └─────────┘
        │
        │ (when internet available)
        ▼
   Cloud Sync API
```

**Flow:**
1. Teacher opens app → selects subject/time slot → generates OTP
2. Teacher's phone starts a local HTTP server on port 8181
3. Students connect to teacher's LAN IP → enter OTP
4. Teacher's SQLite stores all attendance records
5. When internet is available → Teacher syncs to central MySQL server

---

## 🗄️ Backend Setup (Spring Boot)

### Prerequisites
- Java 17+
- Maven 3.8+
- MySQL 8.0+

### Step 1: Database Setup
```sql
-- Run in MySQL:
CREATE DATABASE attendance_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'attendance_user'@'localhost' IDENTIFIED BY 'AttendPass@123';
GRANT ALL PRIVILEGES ON attendance_db.* TO 'attendance_user'@'localhost';
FLUSH PRIVILEGES;
```

### Step 2: Configure application.properties
```properties
# Edit: backend/src/main/resources/application.properties
spring.datasource.url=jdbc:mysql://localhost:3306/attendance_db?useSSL=false&serverTimezone=UTC
spring.datasource.username=attendance_user
spring.datasource.password=AttendPass@123
app.jwt.secret=YourVeryLongSecretKeyHereMustBe256BitsOrMore!
```

### Step 3: Build and Run
```bash
cd backend
mvn clean package -DskipTests
java -jar target/attendance-system-1.0.0.jar
```

Or with Maven:
```bash
mvn spring-boot:run
```

### Step 4: Verify
```bash
# Test login (default admin created on startup)
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@1234"}'
```

Default admin credentials:
- Username: `admin`
- Password: `Admin@1234`
- **⚠️ Change password after first login!**

---

## 📦 REST API Reference

### Authentication
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/login` | None | Login, returns JWT |

### Admin Endpoints (Role: ADMIN)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/admin/teachers` | Register a teacher |
| POST | `/api/admin/students` | Register a student |
| POST | `/api/admin/departments` | Create department |
| GET | `/api/admin/departments` | List departments |
| POST | `/api/admin/subjects` | Create subject |
| GET | `/api/admin/attendance/stats` | Get attendance statistics |
| GET | `/api/admin/attendance/export` | Export Excel file |

### Teacher Endpoints (Role: TEACHER)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/teacher/otp/generate` | Generate OTP for class |
| GET | `/api/teacher/subjects` | Get subjects list |

### Student Endpoints (Role: STUDENT)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/student/attendance` | Get my attendance stats |

### Sync Endpoints (Role: TEACHER)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/sync/attendance` | Bulk sync attendance records |

---

### Register Teacher Example
```bash
TOKEN="<admin_jwt_token>"
curl -X POST http://localhost:8080/api/admin/teachers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "teacher1",
    "email": "teacher1@school.edu",
    "fullName": "Dr. John Smith",
    "employeeId": "EMP001",
    "departmentId": 1,
    "phone": "9876543210"
  }'
# Response includes generated temp password in "token" field
```

### Generate OTP Example
```bash
curl -X POST http://localhost:8080/api/teacher/otp/generate \
  -H "Authorization: Bearer $TEACHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subjectId": 1,
    "timeSlot": "9:00 AM - 10:00 AM"
  }'
```

### Sync Attendance Example
```bash
curl -X POST http://localhost:8080/api/sync/attendance \
  -H "Authorization: Bearer $TEACHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "records": [
      {
        "syncId": "uuid-here",
        "studentId": 1,
        "subjectId": 1,
        "teacherId": 1,
        "attendanceDate": "2025-01-15",
        "timeSlot": "9:00 AM - 10:00 AM",
        "status": "PRESENT",
        "markedAt": "2025-01-15T09:05:00"
      }
    ]
  }'
```

---

## 📱 Flutter App Setup

### Prerequisites
- Flutter SDK 3.16+
- Android Studio or VS Code
- Android device/emulator (API 21+)

### Step 1: Install Dependencies
```bash
cd flutter
flutter pub get
```

### Step 2: Android Permissions
Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<!-- For LAN server (teacher app) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

Also inside `<application>`:
```xml
android:usesCleartextTraffic="true"
```
This is required for LAN HTTP (non-HTTPS) communication on same network.

### Step 3: Run
```bash
flutter run
```

### Step 4: Configure Server URL
On the Login screen → tap "Server Settings" → enter your server IP:
- For development on same machine: `http://10.0.2.2:8080` (Android emulator)
- For real device: `http://192.168.1.xxx:8080` (your computer's IP on LAN)

---

## 🌐 LAN Communication — How It Works

### Teacher Side (HTTP Server on port 8181)

When the teacher generates an OTP:
1. A Dart HTTP server starts on the device using the `shelf` package
2. It binds to `0.0.0.0:8181` (all network interfaces)
3. Server exposes three endpoints:
   - `GET /ping` — health check
   - `GET /session-info` — returns current subject/time slot
   - `POST /validate-otp` — validates OTP and records attendance in SQLite

```dart
// Teacher's server is accessible at:
// http://<teacher_wifi_ip>:8181
```

### Student Side (HTTP Client)

Students connect to the teacher server:
1. **Auto-discovery**: Student app scans `192.168.x.1` to `192.168.x.254` pinging port 8181
2. **Manual IP**: Student enters teacher's IP manually
3. Student enters OTP → POST to teacher's server → attendance recorded

```
Student Device → (LAN WiFi) → Teacher Device:8181 → SQLite
```

### Finding Teacher's IP
On Android: Settings → WiFi → tap connected network → IP Address  
Or in the Teacher app, the IP is displayed when server starts.

### Network Requirements
- Both teacher and students must be on **same WiFi network**
- No internet required for attendance marking
- Internet only needed for syncing to central server

---

## 🔄 Sync Flow

```
Teacher App (SQLite)
      │
      ├── is_synced = 0 (pending records)
      │
      ▼  (when internet available)
POST /api/sync/attendance
      │
      ├── Server checks syncId for duplicates
      ├── Inserts new records
      └── Returns {inserted, skipped, failed}
      │
Teacher App marks records as is_synced = 1
```

**Sync is idempotent** — records with the same `syncId` (UUID) are skipped if already synced. Safe to retry.

---

## 🗃️ Database Schema

```sql
-- Users table (all roles)
CREATE TABLE users (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,  -- BCrypt
  email VARCHAR(100) UNIQUE NOT NULL,
  role ENUM('ADMIN','TEACHER','STUDENT') NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at DATETIME
);

-- Departments
CREATE TABLE departments (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) UNIQUE NOT NULL,
  code VARCHAR(20),
  description TEXT
);

-- Teachers
CREATE TABLE teachers (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT UNIQUE NOT NULL REFERENCES users(id),
  full_name VARCHAR(100) NOT NULL,
  employee_id VARCHAR(50) UNIQUE,
  department_id BIGINT REFERENCES departments(id),
  phone VARCHAR(20)
);

-- Students
CREATE TABLE students (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT UNIQUE NOT NULL REFERENCES users(id),
  full_name VARCHAR(100) NOT NULL,
  roll_number VARCHAR(50) UNIQUE,
  department_id BIGINT REFERENCES departments(id),
  year_of_study INT,
  section VARCHAR(10),
  phone VARCHAR(20)
);

-- Subjects
CREATE TABLE subjects (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  code VARCHAR(20) NOT NULL,
  department_id BIGINT REFERENCES departments(id),
  year_of_study INT,
  credits INT
);

-- Attendance (synced from teacher SQLite)
CREATE TABLE attendance (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  student_id BIGINT NOT NULL REFERENCES students(id),
  subject_id BIGINT NOT NULL REFERENCES subjects(id),
  teacher_id BIGINT NOT NULL REFERENCES teachers(id),
  attendance_date DATE NOT NULL,
  time_slot VARCHAR(50),
  status ENUM('PRESENT','ABSENT','LATE') DEFAULT 'PRESENT',
  marked_at DATETIME,
  sync_id VARCHAR(36) UNIQUE,  -- UUID from SQLite
  synced_at DATETIME,
  INDEX idx_student_subject (student_id, subject_id),
  INDEX idx_date (attendance_date)
);

-- OTP Sessions (server-side tracking)
CREATE TABLE otp_sessions (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  otp VARCHAR(6) NOT NULL,
  teacher_id BIGINT NOT NULL REFERENCES teachers(id),
  subject_id BIGINT NOT NULL REFERENCES subjects(id),
  time_slot VARCHAR(50),
  created_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  is_used BOOLEAN DEFAULT FALSE
);
```

---

## 🔐 Security Details

| Feature | Implementation |
|---------|---------------|
| Passwords | BCrypt (strength 10) |
| Auth tokens | JWT HS256, 24h expiry |
| OTP | SecureRandom 6-digit, 60s expiry |
| Role checking | Spring @PreAuthorize + JWT claims |
| Duplicate sync | UUID syncId deduplication |
| OTP reuse | Marked as used after validation |

---

## 🗂️ Project Structure

```
attendance-system/
├── backend/
│   ├── pom.xml
│   └── src/main/java/com/attendance/
│       ├── AttendanceApplication.java
│       ├── config/
│       │   ├── SecurityConfig.java
│       │   ├── DataInitializer.java
│       │   └── SchedulingConfig.java
│       ├── controller/
│       │   ├── AuthController.java
│       │   ├── AdminController.java
│       │   ├── TeacherController.java
│       │   ├── StudentController.java
│       │   └── SyncController.java
│       ├── dto/
│       │   ├── AuthRequest/Response.java
│       │   ├── ApiResponse.java
│       │   ├── RegisterTeacher/StudentRequest.java
│       │   ├── AttendanceSyncRequest.java
│       │   └── AttendanceStatsResponse.java
│       ├── entity/
│       │   ├── User.java
│       │   ├── Teacher.java
│       │   ├── Student.java
│       │   ├── Department.java
│       │   ├── Subject.java
│       │   ├── Attendance.java
│       │   └── OtpSession.java
│       ├── repository/          (7 JPA repos)
│       ├── security/
│       │   ├── JwtUtil.java
│       │   ├── JwtAuthenticationFilter.java
│       │   └── UserDetailsServiceImpl.java
│       └── service/
│           ├── AuthService.java
│           ├── AdminService.java
│           ├── OtpService.java
│           └── SyncService.java
│
└── flutter/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── models/
        │   ├── user_model.dart
        │   └── attendance_model.dart
        ├── providers/
        │   └── auth_provider.dart
        ├── database/
        │   └── database_service.dart      (SQLite)
        ├── services/
        │   ├── api_service.dart           (Cloud HTTP)
        │   ├── lan_server_service.dart    (Teacher LAN server)
        │   ├── lan_client_service.dart    (Student LAN client)
        │   └── sync_service.dart          (Cloud sync)
        ├── screens/
        │   ├── auth/login_screen.dart
        │   ├── teacher/teacher_dashboard.dart
        │   ├── student/student_dashboard.dart
        │   └── admin/admin_dashboard.dart
        └── widgets/
            └── custom_text_field.dart
```

---

## 🚀 Quick Start Workflow

### 1. Admin Setup (one-time)
```
Login as admin → Create Department → Create Subject → Register Teachers & Students
```

### 2. Daily Teacher Flow
```
Open App → Login → Select Subject & Time Slot → 
Generate OTP → Share IP with students → LAN Server auto-starts
```

### 3. Student Attendance
```
Open App → Login → Connect to Teacher IP → Enter OTP → Done ✅
```

### 4. Sync (when internet available)
```
Teacher App → Tap Sync button → All pending records upload to server
```

---

## 🐛 Troubleshooting

**Students can't connect to teacher:**
- Ensure both are on same WiFi network
- Check `android:usesCleartextTraffic="true"` in AndroidManifest
- Verify port 8181 is not blocked by device firewall
- Try entering teacher's IP manually instead of auto-discover

**JWT token expired:**
- Re-login to get new token
- Default expiry is 24 hours (configurable in application.properties)

**Sync fails:**
- Check internet connectivity
- Verify server URL in app settings
- Check Spring Boot logs for errors

**OTP not working:**
- OTP expires after 60 seconds
- Generate a new OTP if expired
- Ensure teacher server is still running
