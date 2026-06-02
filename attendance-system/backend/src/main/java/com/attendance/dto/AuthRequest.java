// ============================================================
// FILE: dto/AuthRequest.java
// ============================================================
package com.attendance.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class AuthRequest {
    @NotBlank
    private String username;
    @NotBlank
    private String password;
}
