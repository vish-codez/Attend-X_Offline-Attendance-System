package com.attendance.dto;

import lombok.Data;
import java.util.List;

/**
 * Sent by the teacher's device when a session expires.
 * Contains the full context of the class that was held plus the IDs of students
 * who actually marked attendance (PRESENT). The backend uses this to write
 * ABSENT records for every other enrolled student in the same department/year,
 * ensuring total-class counts are accurate for ALL students — not only those
 * who showed up.
 */
@Data
public class FinalizeSessionRequest {
    private Long subjectId;
    private Long teacherId;
    private Integer departmentId;   // used to find enrolled students
    private Integer yearOfStudy;    // used to find enrolled students
    private String attendanceDate;  // "yyyy-MM-dd"
    private String timeSlot;
    /** Student IDs who already have a PRESENT record for this session. */
    private List<Long> presentStudentIds;
}