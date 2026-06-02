package com.attendance.repository;

import com.attendance.entity.Teacher;
import com.attendance.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface TeacherRepository extends JpaRepository<Teacher, Long> {
    Optional<Teacher> findByUser(User user);
    Optional<Teacher> findByUserId(Long userId);
    Optional<Teacher> findByEmployeeId(String employeeId);
}
