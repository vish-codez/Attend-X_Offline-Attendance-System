package com.attendance.config;

import com.attendance.entity.User;
import com.attendance.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
@RequiredArgsConstructor
@Slf4j
public class DataInitializer {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Bean
    public CommandLineRunner initData() {
        return args -> {
            if (!userRepository.existsByUsername("admin")) {
                User admin = User.builder()
                        .username("admin")
                        .email("admin@attendance.local")
                        .password(passwordEncoder.encode("Admin@1234"))
                        .role(User.Role.ADMIN)
                        .isActive(true)
                        .build();
                userRepository.save(admin);
                log.info("✅ Default admin created: username=admin, password=Admin@1234");
            }
        };
    }
}
