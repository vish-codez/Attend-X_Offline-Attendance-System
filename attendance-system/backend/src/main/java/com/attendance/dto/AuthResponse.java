package com.attendance.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AuthResponse {
    private String token;
    private String username;
    private String role;
    private Long userId;
    private String fullName;

    // Student-specific fields
    private String rollNumber;
    private String departmentName;
    private Integer yearOfStudy;
    private String section;

    // Teacher-specific fields
    private String employeeId;
    private String teacherDepartmentName;
}