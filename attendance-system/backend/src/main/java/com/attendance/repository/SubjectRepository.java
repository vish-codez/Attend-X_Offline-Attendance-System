package com.attendance.repository;

import com.attendance.entity.Subject;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface SubjectRepository extends JpaRepository<Subject, Long> {
    List<Subject> findByDepartmentId(Long departmentId);
    List<Subject> findByYearOfStudy(Integer yearOfStudy);
    List<Subject> findByDepartmentIdAndYearOfStudy(Long departmentId, Integer yearOfStudy);
}