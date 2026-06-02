package com.attendance.repository;

import com.attendance.entity.Student;
import com.attendance.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface StudentRepository extends JpaRepository<Student, Long> {
    Optional<Student> findByUser(User user);
    Optional<Student> findByUserId(Long userId);
    Optional<Student> findByRollNumber(String rollNumber);
    List<Student> findByDepartmentId(Long departmentId);
    List<Student> findByYearOfStudy(Integer yearOfStudy);
    List<Student> findByDepartmentIdAndYearOfStudy(Long departmentId, Integer yearOfStudy);
}