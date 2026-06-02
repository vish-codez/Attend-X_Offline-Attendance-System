package com.attendance.dto;

import lombok.Data;
import java.util.List;

@Data
public class AttendanceSyncRequest {
    private List<AttendanceRecord> records;

    @Data
    public static class AttendanceRecord {
        private String syncId;          // UUID from SQLite
        private Long studentId;
        private Long subjectId;
        private Long teacherId;
        private String attendanceDate;  // ISO format: yyyy-MM-dd
        private String timeSlot;
        private String status;          // PRESENT, ABSENT, LATE
        private String markedAt;        // ISO datetime
    }
}
