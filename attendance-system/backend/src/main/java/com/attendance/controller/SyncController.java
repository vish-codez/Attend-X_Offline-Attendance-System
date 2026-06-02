package com.attendance.controller;

import com.attendance.dto.ApiResponse;
import com.attendance.dto.AttendanceSyncRequest;
import com.attendance.dto.FinalizeSessionRequest;
import com.attendance.service.SyncService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/sync")
@RequiredArgsConstructor
public class SyncController {

    private final SyncService syncService;

    @PostMapping("/attendance")
    public ResponseEntity<ApiResponse<Map<String, Object>>> syncAttendance(
            @RequestBody AttendanceSyncRequest request) {

        SyncService.SyncResult result = syncService.syncAttendance(request);

        Map<String, Object> data = Map.of(
                "inserted", result.inserted(),
                "skipped", result.skipped(),
                "failed", result.failed()

        );

        String message = String.format("Sync complete. Inserted: %d, Skipped: %d, Failed: %d",
                result.inserted(), result.skipped(), result.failed());

        return ResponseEntity.ok(ApiResponse.success(message, data));
    }

    /**
     * Called by the teacher's device when a 5-minute session expires.
     * Writes ABSENT records for every enrolled student who did NOT mark
     * attendance — this is what makes percentage calculations correct for
     * students who miss a class.
     */
    @PostMapping("/finalize-session")
    public ResponseEntity<ApiResponse<Map<String, Object>>> finalizeSession(
            @RequestBody FinalizeSessionRequest request) {

        SyncService.FinalizeResult result = syncService.finalizeSession(request);

        Map<String, Object> data = Map.of(
                "absentInserted", result.absentInserted(),
                "skipped", result.skipped(),
                "message", result.message()
        );

        return ResponseEntity.ok(ApiResponse.success(result.message(), data));
    }
}