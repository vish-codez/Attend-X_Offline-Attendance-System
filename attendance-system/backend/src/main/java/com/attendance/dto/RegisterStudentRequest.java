package com.attendance.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class RegisterStudentRequest {
    @NotBlank
    private String username;
    @NotBlank
    @Email
    private String email;
    @NotBlank
    private String fullName;
    private String rollNumber;
    private Long departmentId;
    private Integer yearOfStudy;
    private String section;
    private String password; // optional — generated if not provided
}