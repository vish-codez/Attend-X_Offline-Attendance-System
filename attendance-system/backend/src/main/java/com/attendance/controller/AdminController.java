package com.attendance.controller;

import com.attendance.dto.*;
import com.attendance.entity.Department;
import com.attendance.entity.Student;
import com.attendance.entity.Subject;
import com.attendance.entity.Teacher;
import com.attendance.service.AdminService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    private final AdminService adminService;

    // ── Teachers ──────────────────────────────────────────────────
    @PostMapping("/teachers")
    public ResponseEntity<ApiResponse<AuthResponse>> registerTeacher(
            @Valid @RequestBody RegisterTeacherRequest req) {
        return ResponseEntity.ok(
                ApiResponse.success("Teacher registered", adminService.registerTeacher(req)));
    }

    @GetMapping("/teachers")
    public ResponseEntity<ApiResponse<List<Teacher>>> getTeachers() {
        return ResponseEntity.ok(
                ApiResponse.success(adminService.getAllTeachers()));
    }

    // ── Students ──────────────────────────────────────────────────
    @PostMapping("/students")
    public ResponseEntity<ApiResponse<AuthResponse>> registerStudent(
            @Valid @RequestBody RegisterStudentRequest req) {
        return ResponseEntity.ok(
                ApiResponse.success("Student registered", adminService.registerStudent(req)));
    }

    @GetMapping("/students")
    public ResponseEntity<ApiResponse<List<Student>>> getStudents(
            @RequestParam(required = false) Long departmentId,
            @RequestParam(required = false) Integer yearOfStudy) {
        return ResponseEntity.ok(
                ApiResponse.success(adminService.getAllStudents(departmentId, yearOfStudy)));
    }

    // ── Departments ───────────────────────────────────────────────
    @PostMapping("/departments")
    public ResponseEntity<ApiResponse<Department>> createDepartment(
            @RequestBody Map<String, String> body) {
        Department dept = adminService.createDepartment(
                body.get("name"), body.get("code"), body.get("description"));
        return ResponseEntity.ok(ApiResponse.success("Department created", dept));
    }

    @GetMapping("/departments")
    public ResponseEntity<ApiResponse<List<Department>>> getDepartments() {
        return ResponseEntity.ok(ApiResponse.success(adminService.getAllDepartments()));
    }

    // ── Subjects ──────────────────────────────────────────────────
    @PostMapping("/subjects")
    public ResponseEntity<ApiResponse<Subject>> createSubject(
            @RequestBody Map<String, Object> body) {
        try {
            String name = (String) body.get("name");
            String code = (String) body.get("code");
            Long departmentId = Long.valueOf(body.get("departmentId").toString());
            Integer yearOfStudy = Integer.valueOf(body.get("yearOfStudy").toString());
            Integer credits = body.get("credits") != null
                    ? Integer.valueOf(body.get("credits").toString()) : 3;

            Subject sub = adminService.createSubject(name, code, departmentId, yearOfStudy, credits);
            return ResponseEntity.ok(ApiResponse.success("Subject created", sub));
        } catch (Exception e) {
            return ResponseEntity.badRequest()
                    .body(ApiResponse.error("Error: " + e.getMessage()));
        }
    }

    @GetMapping("/subjects")
    public ResponseEntity<ApiResponse<List<Subject>>> getAllSubjects(
            @RequestParam(required = false) Long departmentId,
            @RequestParam(required = false) Integer yearOfStudy) {
        return ResponseEntity.ok(
                ApiResponse.success(adminService.getAllSubjects(departmentId, yearOfStudy)));
    }

    // ── Attendance Stats ──────────────────────────────────────────
    @GetMapping("/attendance/stats")
    public ResponseEntity<ApiResponse<List<AttendanceStatsResponse>>> getStats(
            @RequestParam(required = false) Long studentId,
            @RequestParam(required = false) Long subjectId,
            @RequestParam(required = false) Long departmentId,
            @RequestParam(required = false) Integer yearOfStudy) {
        return ResponseEntity.ok(ApiResponse.success(
                adminService.getAttendanceStats(studentId, subjectId, departmentId, yearOfStudy)));
    }

    // ── Export Excel ──────────────────────────────────────────────
    @GetMapping("/attendance/export")
    public ResponseEntity<byte[]> exportExcel(
            @RequestParam(required = false) Long subjectId,
            @RequestParam(required = false) Long departmentId,
            @RequestParam(required = false) Integer yearOfStudy) throws IOException {
        byte[] data = adminService.exportAttendanceToExcel(subjectId, departmentId, yearOfStudy);
        String filename = "attendance_"
                + LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE) + ".xlsx";
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=" + filename)
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .body(data);
    }

    // ── Reset Password ────────────────────────────────────────────
    @PostMapping("/reset-password")
    public ResponseEntity<ApiResponse<String>> resetPassword(
            @RequestBody ResetPasswordRequest req) {
        return ResponseEntity.ok(
                adminService.resetPassword(req.getUsername(), req.getNewPassword()));
    }
}