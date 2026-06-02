package com.attendance.service;

import com.attendance.dto.AttendanceSyncRequest;
import com.attendance.dto.FinalizeSessionRequest;
import com.attendance.entity.Attendance;
import com.attendance.entity.Student;
import com.attendance.entity.Subject;
import com.attendance.entity.Teacher;
import com.attendance.repository.AttendanceRepository;
import com.attendance.repository.StudentRepository;
import com.attendance.repository.SubjectRepository;
import com.attendance.repository.TeacherRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;

@Service
@RequiredArgsConstructor
@Slf4j
public class SyncService {

    private final AttendanceRepository attendanceRepository;
    private final StudentRepository studentRepository;
    private final SubjectRepository subjectRepository;
    private final TeacherRepository teacherRepository;

    @Transactional
    public SyncResult syncAttendance(AttendanceSyncRequest request) {
        int inserted = 0, skipped = 0, failed = 0;

        for (AttendanceSyncRequest.AttendanceRecord rec : request.getRecords()) {
            try {
                // Skip duplicates by syncId
                if (rec.getSyncId() != null &&
                        attendanceRepository.existsBySyncId(rec.getSyncId())) {
                    skipped++;
                    continue;
                }

                // Find student
                Optional<Student> studentOpt =
                        studentRepository.findById(rec.getStudentId());
                if (studentOpt.isEmpty()) {
                    log.error("Failed to sync record {}: Student {} not found",
                            rec.getSyncId(), rec.getStudentId());
                    failed++;
                    continue;
                }

                // Find subject
                Optional<Subject> subjectOpt =
                        subjectRepository.findById(rec.getSubjectId());
                if (subjectOpt.isEmpty()) {
                    log.error("Failed to sync record {}: Subject {} not found",
                            rec.getSyncId(), rec.getSubjectId());
                    failed++;
                    continue;
                }

                // Find teacher — try by ID first, fallback to student's dept teacher
                Teacher teacher = null;
                if (rec.getTeacherId() != null) {
                    Optional<Teacher> teacherOpt =
                            teacherRepository.findById(rec.getTeacherId());
                    if (teacherOpt.isPresent()) {
                        teacher = teacherOpt.get();
                    }
                }
                // If teacher not found, try to find any teacher for this subject
                if (teacher == null) {
                    List<Teacher> teachers = teacherRepository.findAll();
                    if (!teachers.isEmpty()) {
                        teacher = teachers.get(0); // fallback to first teacher
                        log.warn("Teacher {} not found for record {}, using fallback teacher {}",
                                rec.getTeacherId(), rec.getSyncId(), teacher.getId());
                    } else {
                        log.error("No teachers found in database, cannot sync record {}",
                                rec.getSyncId());
                        failed++;
                        continue;
                    }
                }

                // Parse date
                LocalDate attendanceDate = LocalDate.parse(
                        rec.getAttendanceDate(),
                        DateTimeFormatter.ISO_LOCAL_DATE);

                // Parse marked_at
                LocalDateTime markedAt = null;
                if (rec.getMarkedAt() != null) {
                    try {
                        markedAt = LocalDateTime.parse(rec.getMarkedAt(),
                                DateTimeFormatter.ISO_DATE_TIME);
                    } catch (Exception e) {
                        markedAt = LocalDateTime.now();
                    }
                }

                Attendance attendance = Attendance.builder()
                        .student(studentOpt.get())
                        .subject(subjectOpt.get())
                        .teacher(teacher)
                        .attendanceDate(attendanceDate)
                        .timeSlot(rec.getTimeSlot())
                        .status(rec.getStatus() != null
                                ? Attendance.Status.valueOf(rec.getStatus())
                                : Attendance.Status.PRESENT)
                        .syncId(rec.getSyncId())
                        .markedAt(markedAt != null ? markedAt : LocalDateTime.now())
                        .build();

                attendanceRepository.save(attendance);
                inserted++;

            } catch (Exception e) {
                log.error("Failed to sync record {}: {}",
                        rec.getSyncId(), e.getMessage());
                failed++;
            }
        }

        return new SyncResult(inserted, skipped, failed);
    }

    public record SyncResult(int inserted, int skipped, int failed) {}

    // ── Finalize Session — fill ABSENT for non-attending students ─────────────
    /**
     * Called once when a teacher's 5-minute session expires.
     *
     * The teacher device sends the subject, date, timeslot, and the list of
     * student IDs who already have PRESENT records.  This method finds every
     * other student enrolled in the same department + year and writes an ABSENT
     * record for them — but only if they don't already have ANY record for
     * this exact subject / date / timeslot (guards against double-calls).
     *
     * This is the key fix: previously total-class count == present count for
     * absent students (they had no rows), making their percentage always 100 %.
     * Now every held class produces a row for every enrolled student.
     */
    @Transactional
    public FinalizeResult finalizeSession(FinalizeSessionRequest req) {
        int absentInserted = 0;
        int skipped = 0;

        Subject subject = subjectRepository.findById(req.getSubjectId())
                .orElse(null);
        if (subject == null) {
            log.error("finalizeSession: subject {} not found", req.getSubjectId());
            return new FinalizeResult(0, 0, "Subject not found");
        }

        Teacher teacher = null;
        if (req.getTeacherId() != null) {
            teacher = teacherRepository.findById(req.getTeacherId()).orElse(null);
        }
        if (teacher == null) {
            List<Teacher> all = teacherRepository.findAll();
            if (!all.isEmpty()) teacher = all.get(0);
        }
        if (teacher == null) {
            return new FinalizeResult(0, 0, "No teacher found in database");
        }

        LocalDate date = LocalDate.parse(req.getAttendanceDate(),
                DateTimeFormatter.ISO_LOCAL_DATE);

        // All students in same dept + year (the "class")
        List<Student> enrolled;
        if (req.getDepartmentId() != null && req.getYearOfStudy() != null) {
            enrolled = studentRepository.findByDepartmentIdAndYearOfStudy(
                    Long.valueOf(req.getDepartmentId()), req.getYearOfStudy());
        } else if (req.getDepartmentId() != null) {
            enrolled = studentRepository.findByDepartmentId(
                    Long.valueOf(req.getDepartmentId()));
        } else {
            // Fallback: all students (shouldn't happen in practice)
            enrolled = studentRepository.findAll();
        }

        Set<Long> presentIds = req.getPresentStudentIds() == null
                ? Set.of()
                : Set.copyOf(req.getPresentStudentIds());

        for (Student student : enrolled) {
            if (presentIds.contains(student.getId())) {
                // Already marked PRESENT — nothing to do
                skipped++;
                continue;
            }

            // Guard: check if a record already exists for this slot
            // (handles duplicate finalize calls gracefully)
            boolean alreadyExists = attendanceRepository
                    .existsByStudentIdAndSubjectIdAndAttendanceDateAndTimeSlot(
                            student.getId(), subject.getId(), date, req.getTimeSlot());
            if (alreadyExists) {
                skipped++;
                continue;
            }

            Attendance absent = Attendance.builder()
                    .student(student)
                    .subject(subject)
                    .teacher(teacher)
                    .attendanceDate(date)
                    .timeSlot(req.getTimeSlot())
                    .status(Attendance.Status.ABSENT)
                    .markedAt(LocalDateTime.now())
                    .syncedAt(LocalDateTime.now())
                    // syncId is null for server-generated ABSENT records
                    .build();

            attendanceRepository.save(absent);
            absentInserted++;
            log.info("Marked ABSENT: student={} subject={} date={} slot={}",
                    student.getId(), subject.getId(), date, req.getTimeSlot());
        }

        String msg = String.format(
                "Session finalized. Absent records inserted: %d, already present/recorded: %d",
                absentInserted, skipped);
        log.info(msg);
        return new FinalizeResult(absentInserted, skipped, msg);
    }

    public record FinalizeResult(int absentInserted, int skipped, String message) {}
}