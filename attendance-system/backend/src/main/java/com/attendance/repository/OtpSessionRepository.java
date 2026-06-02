package com.attendance.repository;

import com.attendance.entity.OtpSession;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface OtpSessionRepository extends JpaRepository<OtpSession, Long> {
    Optional<OtpSession> findByOtpAndIsUsedFalse(String otp);
    void deleteByExpiresAtBefore(LocalDateTime dateTime);
    List<OtpSession> findByTeacherIdAndIsUsedFalse(Long teacherId);
}
