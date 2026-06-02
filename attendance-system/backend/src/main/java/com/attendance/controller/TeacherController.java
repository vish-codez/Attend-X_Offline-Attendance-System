package com.attendance.controller;

import com.attendance.dto.ApiResponse;
import com.attendance.entity.OtpSession;
import com.attendance.entity.Subject;
import com.attendance.repository.SubjectRepository;
import com.attendance.service.OtpService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/teacher")
@RequiredArgsConstructor
public class TeacherController {

    private final OtpService otpService;
    private final SubjectRepository subjectRepository;

    // Generate OTP for a class session
    @PostMapping("/otp/generate")
    public ResponseEntity<ApiResponse<Map<String, Object>>> generateOtp(
            Authentication auth,
            @RequestBody Map<String, Object> body) {

        Long subjectId = Long.valueOf(body.get("subjectId").toString());
        String timeSlot = (String) body.get("timeSlot");

        OtpSession session = otpService.generateOtp(auth.getName(), subjectId, timeSlot);

        Map<String, Object> response = Map.of(
                "otp", session.getOtp(),
                "expiresAt", session.getExpiresAt().toString(),
                "sessionId", session.getId()
        );
        return ResponseEntity.ok(ApiResponse.success("OTP generated", response));
    }

    // Get subjects for teacher's department
    @GetMapping("/subjects")
    public ResponseEntity<ApiResponse<List<Subject>>> getSubjects(
            @RequestParam(required = false) Long departmentId,
            @RequestParam(required = false) Integer yearOfStudy) {

        List<Subject> subjects;
        if (departmentId != null && yearOfStudy != null) {
            subjects = subjectRepository.findByDepartmentIdAndYearOfStudy(departmentId, yearOfStudy);
        } else if (departmentId != null) {
            subjects = subjectRepository.findByDepartmentId(departmentId);
        } else {
            subjects = subjectRepository.findAll();
        }
        return ResponseEntity.ok(ApiResponse.success(subjects));
    }
}
