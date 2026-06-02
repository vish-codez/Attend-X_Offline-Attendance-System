import 'package:uuid/uuid.dart';

class AttendanceRecord {
  final String syncId;
  final int studentId;
  final String? studentName;  // saved for teacher's Students Present view
  final int subjectId;
  final String? subjectName;  // saved for student's offline attendance view
  final int teacherId;
  final String attendanceDate;
  final String timeSlot;
  final String status;
  final String markedAt;
  bool isSynced;

  AttendanceRecord({
    String? syncId,
    required this.studentId,
    this.studentName,
    required this.subjectId,
    this.subjectName,
    required this.teacherId,
    required this.attendanceDate,
    required this.timeSlot,
    required this.status,
    required this.markedAt,
    this.isSynced = false,
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() => {
    'sync_id': syncId,
    'student_id': studentId,
    'student_name': studentName,
    'subject_id': subjectId,
    'subject_name': subjectName,
    'teacher_id': teacherId,
    'attendance_date': attendanceDate,
    'time_slot': timeSlot,
    'status': status,
    'marked_at': markedAt,
    'is_synced': isSynced ? 1 : 0,
  };

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      syncId: map['sync_id'],
      studentId: map['student_id'],
      studentName: map['student_name'] as String?,
      subjectId: map['subject_id'],
      subjectName: map['subject_name'] as String?,
      teacherId: map['teacher_id'],
      attendanceDate: map['attendance_date'],
      timeSlot: map['time_slot'] ?? '',
      status: map['status'],
      markedAt: map['marked_at'],
      isSynced: map['is_synced'] == 1,
    );
  }

  Map<String, dynamic> toSyncJson() => {
    'syncId': syncId,
    'studentId': studentId,
    'subjectId': subjectId,
    'teacherId': teacherId,
    'attendanceDate': attendanceDate,
    'timeSlot': timeSlot,
    'status': status,
    'markedAt': markedAt,
  };
}

class OtpSession {
  final String otp;
  final int subjectId;
  final int teacherId;
  final String timeSlot;
  final DateTime expiresAt;

  const OtpSession({
    required this.otp,
    required this.subjectId,
    required this.teacherId,
    required this.timeSlot,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class AttendanceStats {
  final int studentId;
  final String studentName;
  final String rollNumber;
  final int subjectId;
  final String subjectName;
  final int totalClasses;
  final int presentCount;
  final double percentage;

  const AttendanceStats({
    required this.studentId,
    required this.studentName,
    required this.rollNumber,
    required this.subjectId,
    required this.subjectName,
    required this.totalClasses,
    required this.presentCount,
    required this.percentage,
  });

  factory AttendanceStats.fromJson(Map<String, dynamic> json) {
    return AttendanceStats(
      studentId: json['studentId'] ?? 0,
      studentName: json['studentName'] ?? '',
      rollNumber: json['rollNumber'] ?? '',
      subjectId: json['subjectId'] ?? 0,
      subjectName: json['subjectName'] ?? '',
      totalClasses: json['totalClasses'] ?? 0,
      presentCount: json['presentCount'] ?? 0,
      percentage: (json['percentage'] ?? 0.0).toDouble(),
    );
  }
}