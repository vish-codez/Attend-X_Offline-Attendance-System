package com.attendance.service;

import com.attendance.dto.AuthRequest;
import com.attendance.dto.AuthResponse;
import com.attendance.entity.Student;
import com.attendance.entity.Teacher;
import com.attendance.entity.User;
import com.attendance.repository.StudentRepository;
import com.attendance.repository.TeacherRepository;
import com.attendance.repository.UserRepository;
import com.attendance.security.JwtUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final AuthenticationManager authenticationManager;
    private final UserDetailsService userDetailsService;
    private final UserRepository userRepository;
    private final TeacherRepository teacherRepository;
    private final StudentRepository studentRepository;
    private final JwtUtil jwtUtil;

    public AuthResponse login(AuthRequest request) {
        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                        request.getUsername(), request.getPassword()));

        User user = userRepository.findByUsername(request.getUsername())
                .orElseThrow(() -> new RuntimeException("User not found"));

        UserDetails userDetails =
                userDetailsService.loadUserByUsername(request.getUsername());
        String token = jwtUtil.generateToken(userDetails, user.getRole().name());

        AuthResponse.AuthResponseBuilder builder = AuthResponse.builder()
                .token(token)
                .username(user.getUsername())
                .role(user.getRole().name());

        switch (user.getRole()) {
            case TEACHER -> {
                Teacher teacher = teacherRepository.findByUser(user)
                        .orElse(null);
                if (teacher != null) {
                    builder.userId(teacher.getId())
                            .fullName(teacher.getFullName())
                            .employeeId(teacher.getEmployeeId())
                            .teacherDepartmentName(
                                    teacher.getDepartment() != null
                                            ? teacher.getDepartment().getName()
                                            : null);
                } else {
                    builder.userId(user.getId()).fullName(user.getUsername());
                }
            }
            case STUDENT -> {
                Student student = studentRepository.findByUser(user)
                        .orElse(null);
                if (student != null) {
                    builder.userId(student.getId())
                            .fullName(student.getFullName())
                            .rollNumber(student.getRollNumber())
                            .yearOfStudy(student.getYearOfStudy())
                            .section(student.getSection())
                            .departmentName(
                                    student.getDepartment() != null
                                            ? student.getDepartment().getName()
                                            : null);
                } else {
                    builder.userId(user.getId()).fullName(user.getUsername());
                }
            }
            case ADMIN -> {
                builder.userId(user.getId()).fullName("Administrator");
            }
        }

        return builder.build();
    }
}