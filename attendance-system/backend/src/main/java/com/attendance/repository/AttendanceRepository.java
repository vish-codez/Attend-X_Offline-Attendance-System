package com.attendance.repository;

import com.attendance.entity.Attendance;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface AttendanceRepository extends JpaRepository<Attendance, Long> {

    boolean existsBySyncId(String syncId);

    Optional<Attendance> findBySyncId(String syncId);

    List<Attendance> findByStudentId(Long studentId);

    List<Attendance> findByStudentIdAndSubjectId(Long studentId, Long subjectId);

    List<Attendance> findBySubjectIdAndAttendanceDate(Long subjectId, LocalDate date);

    /**
     * Guards against duplicate ABSENT records when finalizeSession is called
     * more than once for the same slot (e.g. network retry).
     */
    boolean existsByStudentIdAndSubjectIdAndAttendanceDateAndTimeSlot(
            Long studentId, Long subjectId, LocalDate attendanceDate, String timeSlot);

    @Query("SELECT COUNT(a) FROM Attendance a WHERE a.student.id = :studentId AND a.subject.id = :subjectId AND a.status = 'PRESENT'")
    long countPresent(@Param("studentId") Long studentId, @Param("subjectId") Long subjectId);

    @Query("SELECT COUNT(a) FROM Attendance a WHERE a.student.id = :studentId AND a.subject.id = :subjectId")
    long countTotal(@Param("studentId") Long studentId, @Param("subjectId") Long subjectId);

    /**
     * Counts how many distinct classes (date + timeSlot pairs) were actually
     * held for a subject — regardless of which student's rows we look at.
     * This is the true "total classes conducted" denominator for percentage.
     *
     * Uses a native query because JPQL COUNT(DISTINCT CONCAT(...)) is not
     * supported by all JPA providers. The native query works on MySQL/MariaDB.
     */
    @Query(value = "SELECT COUNT(*) FROM (" +
            "SELECT DISTINCT attendance_date, time_slot FROM attendance " +
            "WHERE subject_id = :subjectId) AS distinct_slots",
            nativeQuery = true)
    long countTotalClassesHeld(@Param("subjectId") Long subjectId);

    @Query("SELECT a FROM Attendance a WHERE a.student.id = :studentId AND a.attendanceDate BETWEEN :from AND :to")
    List<Attendance> findByStudentAndDateRange(@Param("studentId") Long studentId,
                                               @Param("from") LocalDate from,
                                               @Param("to") LocalDate to);

    @Query("SELECT a FROM Attendance a WHERE a.teacher.id = :teacherId AND a.attendanceDate = :date")
    List<Attendance> findByTeacherAndDate(@Param("teacherId") Long teacherId, @Param("date") LocalDate date);
}
