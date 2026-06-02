package com.attendance.service;

import com.attendance.dto.*;
import com.attendance.entity.*;
import com.attendance.repository.*;
import lombok.RequiredArgsConstructor;
import org.apache.poi.ss.usermodel.*;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class AdminService {

    private final UserRepository userRepository;
    private final TeacherRepository teacherRepository;
    private final StudentRepository studentRepository;
    private final DepartmentRepository departmentRepository;
    private final SubjectRepository subjectRepository;
    private final AttendanceRepository attendanceRepository;
    private final PasswordEncoder passwordEncoder;

    // ── Teacher Registration ──────────────────────────────────────
    @Transactional
    public AuthResponse registerTeacher(RegisterTeacherRequest req) {
        if (userRepository.existsByUsername(req.getUsername()))
            throw new RuntimeException("Username already taken");
        if (userRepository.existsByEmail(req.getEmail()))
            throw new RuntimeException("Email already registered");

        String rawPassword = req.getPassword() != null ? req.getPassword() : generatePassword();

        User user = User.builder()
                .username(req.getUsername())
                .email(req.getEmail())
                .password(passwordEncoder.encode(rawPassword))
                .role(User.Role.TEACHER)
                .isActive(true)
                .build();
        userRepository.save(user);

        Department dept = req.getDepartmentId() != null
                ? departmentRepository.findById(req.getDepartmentId()).orElse(null) : null;

        Teacher teacher = Teacher.builder()
                .user(user)
                .fullName(req.getFullName())
                .employeeId(req.getEmployeeId() != null
                        ? req.getEmployeeId()
                        : "EMP-" + UUID.randomUUID().toString().substring(0, 6).toUpperCase())
                .department(dept)
                .build();
        teacherRepository.save(teacher);

        return AuthResponse.builder()
                .username(user.getUsername())
                .role("TEACHER")
                .userId(teacher.getId())
                .fullName(teacher.getFullName())
                .token(rawPassword)
                .build();
    }

    @SuppressWarnings("unchecked")
    public List<Teacher> getAllTeachers() {
        return teacherRepository.findAll();
    }

    // ── Student Registration ──────────────────────────────────────
    @Transactional
    public AuthResponse registerStudent(RegisterStudentRequest req) {
        if (userRepository.existsByUsername(req.getUsername()))
            throw new RuntimeException("Username already taken");
        if (userRepository.existsByEmail(req.getEmail()))
            throw new RuntimeException("Email already registered");

        String rawPassword = req.getPassword() != null ? req.getPassword() : generatePassword();

        User user = User.builder()
                .username(req.getUsername())
                .email(req.getEmail())
                .password(passwordEncoder.encode(rawPassword))
                .role(User.Role.STUDENT)
                .isActive(true)
                .build();
        userRepository.save(user);

        Department dept = req.getDepartmentId() != null
                ? departmentRepository.findById(req.getDepartmentId()).orElse(null) : null;

        Student student = Student.builder()
                .user(user)
                .fullName(req.getFullName())
                .rollNumber(req.getRollNumber())
                .department(dept)
                .yearOfStudy(req.getYearOfStudy())
                .section(req.getSection())
                .build();
        studentRepository.save(student);

        return AuthResponse.builder()
                .username(user.getUsername())
                .role("STUDENT")
                .userId(student.getId())
                .fullName(student.getFullName())
                .token(rawPassword)
                .build();
    }

    public List<Student> getAllStudents(Long departmentId, Integer yearOfStudy) {
        if (departmentId != null && yearOfStudy != null) {
            return studentRepository.findByDepartmentIdAndYearOfStudy(departmentId, yearOfStudy);
        } else if (departmentId != null) {
            return studentRepository.findByDepartmentId(departmentId);
        } else if (yearOfStudy != null) {
            return studentRepository.findByYearOfStudy(yearOfStudy);
        }
        return studentRepository.findAll();
    }

    // ── Department CRUD ───────────────────────────────────────────
    @Transactional
    public Department createDepartment(String name, String code, String description) {
        Department dept = Department.builder()
                .name(name).code(code).description(description).build();
        return departmentRepository.save(dept);
    }

    public List<Department> getAllDepartments() {
        return departmentRepository.findAll();
    }

    // ── Subject CRUD ──────────────────────────────────────────────
    @Transactional
    public Subject createSubject(String name, String code, Long deptId,
                                 Integer year, Integer credits) {
        Department dept = departmentRepository.findById(deptId)
                .orElseThrow(() -> new RuntimeException("Department not found"));
        Subject subject = Subject.builder()
                .name(name).code(code).department(dept)
                .yearOfStudy(year).credits(credits).build();
        return subjectRepository.save(subject);
    }

    public List<Subject> getAllSubjects(Long departmentId, Integer yearOfStudy) {
        if (departmentId != null && yearOfStudy != null) {
            return subjectRepository.findByDepartmentIdAndYearOfStudy(departmentId, yearOfStudy);
        } else if (departmentId != null) {
            return subjectRepository.findByDepartmentId(departmentId);
        } else if (yearOfStudy != null) {
            return subjectRepository.findByYearOfStudy(yearOfStudy);
        }
        return subjectRepository.findAll();
    }

    // ── Attendance Stats ──────────────────────────────────────────
    public List<AttendanceStatsResponse> getAttendanceStats(
            Long studentId, Long subjectId, Long departmentId, Integer yearOfStudy) {

        List<Subject> subjects;
        if (subjectId != null) {
            subjects = List.of(subjectRepository.findById(subjectId).orElseThrow());
        } else if (departmentId != null && yearOfStudy != null) {
            subjects = subjectRepository.findByDepartmentIdAndYearOfStudy(departmentId, yearOfStudy);
        } else if (departmentId != null) {
            subjects = subjectRepository.findByDepartmentId(departmentId);
        } else {
            subjects = subjectRepository.findAll();
        }

        List<Student> students;
        if (studentId != null) {
            students = List.of(studentRepository.findById(studentId).orElseThrow());
        } else if (departmentId != null && yearOfStudy != null) {
            students = studentRepository.findByDepartmentIdAndYearOfStudy(departmentId, yearOfStudy);
        } else if (departmentId != null) {
            students = studentRepository.findByDepartmentId(departmentId);
        } else {
            students = studentRepository.findAll();
        }

        return students.stream()
                .flatMap(s -> subjects.stream().map(sub -> {
                    // Total classes HELD for this subject (across all students).
                    // This is the correct denominator — not the student's own row count,
                    // which would be 0 for absent students and give a false 100%.
                    long totalHeld = attendanceRepository.countTotalClassesHeld(sub.getId());
                    long present = attendanceRepository.countPresent(s.getId(), sub.getId());

                    // Fallback: if no sessions have been finalized yet (legacy data),
                    // countTotalClassesHeld may still be 0 — use the student's own
                    // row count so old records still display something.
                    long total = totalHeld > 0 ? totalHeld
                            : attendanceRepository.countTotal(s.getId(), sub.getId());

                    double pct = total == 0 ? 0
                            : Math.round((present * 100.0 / total) * 100.0) / 100.0;
                    return AttendanceStatsResponse.builder()
                            .studentId(s.getId())
                            .studentName(s.getFullName())
                            .rollNumber(s.getRollNumber())
                            .subjectId(sub.getId())
                            .subjectName(sub.getName())
                            .totalClasses(total)
                            .presentCount(present)
                            .percentage(pct)
                            .build();
                }))
                .filter(r -> r.getTotalClasses() > 0)
                .toList();
    }

    // ── Excel Export with dept/year filters ───────────────────────
    public byte[] exportAttendanceToExcel(Long subjectId,
                                          Long departmentId, Integer yearOfStudy) throws IOException {

        List<AttendanceStatsResponse> stats =
                getAttendanceStats(null, subjectId, departmentId, yearOfStudy);

        try (Workbook workbook = new XSSFWorkbook()) {
            Sheet sheet = workbook.createSheet("Attendance");

            // Header style
            CellStyle headerStyle = workbook.createCellStyle();
            Font font = workbook.createFont();
            font.setBold(true);
            font.setFontHeightInPoints((short) 11);
            headerStyle.setFont(font);
            headerStyle.setFillForegroundColor(IndexedColors.LIGHT_BLUE.getIndex());
            headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
            headerStyle.setBorderBottom(BorderStyle.THIN);

            // Low attendance style (red)
            CellStyle redStyle = workbook.createCellStyle();
            redStyle.setFillForegroundColor(IndexedColors.ROSE.getIndex());
            redStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);

            // Header row
            String[] columns = {
                    "Roll No", "Student Name", "Subject",
                    "Total Classes", "Present", "Absent", "Percentage"
            };
            Row header = sheet.createRow(0);
            for (int i = 0; i < columns.length; i++) {
                Cell cell = header.createCell(i);
                cell.setCellValue(columns[i]);
                cell.setCellStyle(headerStyle);
            }

            // Data rows
            int rowNum = 1;
            for (AttendanceStatsResponse s : stats) {
                Row row = sheet.createRow(rowNum++);
                row.createCell(0).setCellValue(s.getRollNumber());
                row.createCell(1).setCellValue(s.getStudentName());
                row.createCell(2).setCellValue(s.getSubjectName());
                row.createCell(3).setCellValue(s.getTotalClasses());
                row.createCell(4).setCellValue(s.getPresentCount());
                row.createCell(5).setCellValue(s.getTotalClasses() - s.getPresentCount());
                Cell pctCell = row.createCell(6);
                pctCell.setCellValue(s.getPercentage() + "%");
                // Highlight low attendance in red
                if (s.getPercentage() < 75) {
                    pctCell.setCellStyle(redStyle);
                }
            }

            // Auto-size columns
            for (int i = 0; i < columns.length; i++) {
                sheet.autoSizeColumn(i);
            }

            ByteArrayOutputStream out = new ByteArrayOutputStream();
            workbook.write(out);
            return out.toByteArray();
        }
    }

    // ── Reset Password ────────────────────────────────────────────
    @Transactional
    public ApiResponse<String> resetPassword(String username, String newPassword) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found: " + username));
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
        return ApiResponse.<String>builder()
                .success(true)
                .message("Password reset successful for: " + username)
                .data(username)
                .build();
    }

    private String generatePassword() {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#$";
        StringBuilder sb = new StringBuilder();
        java.util.Random rnd = new java.security.SecureRandom();
        for (int i = 0; i < 10; i++) sb.append(chars.charAt(rnd.nextInt(chars.length())));
        return sb.toString();
    }
}