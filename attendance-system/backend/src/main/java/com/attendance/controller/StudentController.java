package com.attendance.controller;

import com.attendance.dto.ApiResponse;
import com.attendance.dto.AttendanceStatsResponse;
import com.attendance.entity.User;
import com.attendance.repository.StudentRepository;
import com.attendance.repository.UserRepository;
import com.attendance.service.AdminService;
import com.attendance.service.OtpService;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/student")
@RequiredArgsConstructor
public class StudentController {

    private final AdminService adminService;
    private final StudentRepository studentRepository;
    private final UserRepository userRepository;
    private final OtpService otpService;

    @GetMapping("/attendance")
    public ResponseEntity<ApiResponse<List<AttendanceStatsResponse>>> getMyAttendance(
            Authentication auth) {
        User user = userRepository.findByUsername(auth.getName())
                .orElseThrow(() -> new RuntimeException("User not found"));
        var student = studentRepository.findByUser(user)
                .orElseThrow(() -> new RuntimeException("Student not found"));
        // Fixed: pass null for the two new parameters (departmentId, yearOfStudy)
        List<AttendanceStatsResponse> stats =
                adminService.getAttendanceStats(student.getId(), null, null, null);
        return ResponseEntity.ok(ApiResponse.success(stats));
    }

    @PostMapping("/otp/verify")
    public ResponseEntity<ApiResponse<String>> verifyOtp(
            @RequestBody OtpVerifyRequest req,
            Authentication auth) {
        User user = userRepository.findByUsername(auth.getName())
                .orElseThrow(() -> new RuntimeException("User not found"));
        var student = studentRepository.findByUser(user)
                .orElseThrow(() -> new RuntimeException("Student not found"));
        boolean valid = otpService.verifyOtp(req.getOtp(), req.getSubjectId(), student.getId());
        if (valid) {
            return ResponseEntity.ok(ApiResponse.success("Attendance marked successfully"));
        } else {
            return ResponseEntity.badRequest()
                    .body(ApiResponse.<String>builder()
                            .success(false)
                            .message("Invalid or expired OTP")
                            .build());
        }
    }

    @Data
    static class OtpVerifyRequest {
        private String otp;
        private Long subjectId;
    }
}