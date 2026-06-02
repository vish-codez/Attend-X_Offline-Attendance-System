package com.attendance.service;

import com.attendance.entity.OtpSession;
import com.attendance.entity.Subject;
import com.attendance.entity.Teacher;
import com.attendance.entity.User;
import com.attendance.repository.OtpSessionRepository;
import com.attendance.repository.SubjectRepository;
import com.attendance.repository.TeacherRepository;
import com.attendance.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor
public class OtpService {

    private final OtpSessionRepository otpSessionRepository;
    private final TeacherRepository teacherRepository;
    private final SubjectRepository subjectRepository;
    private final UserRepository userRepository;

    @Value("${app.otp.expiry-seconds:60}")
    private int otpExpirySeconds;

    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    // ──────────────────────────────────────────────────────────────
    // Generate OTP (called from Teacher App via LAN server,
    // or via cloud sync endpoint)
    // ──────────────────────────────────────────────────────────────
    @Transactional
    public OtpSession generateOtp(String username, Long subjectId, String timeSlot) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found"));
        Teacher teacher = teacherRepository.findByUser(user)
                .orElseThrow(() -> new RuntimeException("Teacher not found"));
        Subject subject = subjectRepository.findById(subjectId)
                .orElseThrow(() -> new RuntimeException("Subject not found"));

        String otp = generateSecureOtp();
        LocalDateTime now = LocalDateTime.now();

        OtpSession session = OtpSession.builder()
                .otp(otp)
                .teacher(teacher)
                .subject(subject)
                .timeSlot(timeSlot)
                .createdAt(now)
                .expiresAt(now.plusSeconds(otpExpirySeconds))
                .isUsed(false)
                .build();

        return otpSessionRepository.save(session);
    }

    // ──────────────────────────────────────────────────────────────
    // Validate OTP
    // ──────────────────────────────────────────────────────────────
    @Transactional
    public OtpSession validateOtp(String otp) {
        OtpSession session = otpSessionRepository.findByOtpAndIsUsedFalse(otp)
                .orElseThrow(() -> new RuntimeException("Invalid or already used OTP"));

        if (session.isExpired()) {
            throw new RuntimeException("OTP has expired");
        }

        return session;
    }

    // ──────────────────────────────────────────────────────────────
    // Cleanup expired OTPs every 5 minutes
    // ──────────────────────────────────────────────────────────────
    @Scheduled(fixedRate = 300_000)
    @Transactional
    public void cleanupExpiredOtps() {
        otpSessionRepository.deleteByExpiresAtBefore(LocalDateTime.now());
    }

    private String generateSecureOtp() {
        int otp = SECURE_RANDOM.nextInt(900000) + 100000; // Guaranteed 6 digits
        return String.valueOf(otp);
    }

    @Transactional
    public boolean verifyOtp(String otp, Long subjectId, Long studentId) {
        OtpSession session = otpSessionRepository.findByOtpAndIsUsedFalse(otp)
                .orElse(null);

        if (session == null) return false;
        if (session.isExpired()) return false;
        if (!session.getSubject().getId().equals(subjectId)) return false;

        session.setIsUsed(true);
        otpSessionRepository.save(session);
        return true;
    }
}
