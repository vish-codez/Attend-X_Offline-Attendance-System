import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/lan_server_service.dart';
import '../../services/sync_service.dart';
import '../../database/database_service.dart';
import '../../models/attendance_model.dart';

class TeacherDashboard extends ConsumerStatefulWidget {
  const TeacherDashboard({super.key});

  @override
  ConsumerState<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends ConsumerState<TeacherDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Class setup
  List<dynamic> _departments = [];
  List<dynamic> _allSubjects = [];
  List<dynamic> _filteredSubjects = [];
  int? _selectedDeptId;
  String? _selectedDeptName;
  int? _selectedYear;
  int? _selectedSubjectId;
  String? _selectedSubjectName;
  String _selectedTimeSlot = '9:00 AM - 10:00 AM';

  // OTP & Server
  String? _currentOtp;
  Timer? _otpTimer;
  int _otpCountdown = 0;
  bool _serverRunning = false;
  String? _serverIp;
  String? _roomCode;
  bool _isGenerating = false;

  // ── Mandatory 5-minute session ────────────────────────────────
  // Once started, cannot be stopped manually — auto-stops after 5 min
  static const int sessionDurationSeconds = 300;
  Timer? _sessionTimer;
  int _sessionCountdown = 0;
  bool _sessionExpired = false;
  bool _sessionStarted = false; // true once first OTP generated

  // Snapshot of the active session — needed for finalizeSession() call
  // even after dropdowns are cleared on expiry.
  int? _sessionSubjectId;
  int? _sessionTeacherId;
  int? _sessionDeptId;
  int? _sessionYear;
  String? _sessionTimeSlot;
  String? _sessionDate;

  // Students & Sync
  List<AttendanceRecord> _todayAttendance = [];
  bool _loadingAttendance = false;
  bool _isSyncing = false;
  int _unsyncedCount = 0;

  final List<String> _timeSlots = [
    '8:00 AM - 9:00 AM', '9:00 AM - 10:00 AM', '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM', '12:00 PM - 1:00 PM', '1:00 PM - 2:00 PM',
    '2:00 PM - 3:00 PM', '3:00 PM - 4:00 PM', '4:00 PM - 5:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) _loadTodayAttendance();
    });
    _loadDepartments();
    _loadAllSubjects();
    _loadUnsyncedCount();
  }

  Future<void> _loadDepartments() async {
    try {
      final depts = await ApiService.instance.getDepartments();
      if (mounted) setState(() => _departments = depts);
    } catch (_) {}
  }

  Future<void> _loadAllSubjects() async {
    try {
      final subjects = await ApiService.instance.getSubjects();
      if (mounted) setState(() => _allSubjects = subjects);
      // Cache subject names for offline use
      await DatabaseService.instance.cacheSubjects(subjects);
    } catch (_) {}
  }

  void _filterSubjects() {
    setState(() {
      _filteredSubjects = _allSubjects.where((s) {
        final dept = s['department'];
        final deptId = dept != null ? dept['id'] as int? : null;
        final year = s['yearOfStudy'] as int?;
        return (_selectedDeptId == null || deptId == _selectedDeptId) &&
            (_selectedYear == null || year == _selectedYear);
      }).toList();

      if (_selectedSubjectId != null &&
          !_filteredSubjects.any((s) => s['id'] == _selectedSubjectId)) {
        _selectedSubjectId = null;
        _selectedSubjectName = null;
      }
    });
  }

  Future<void> _loadUnsyncedCount() async {
    final records = await DatabaseService.instance.getUnsyncedRecords();
    if (mounted) setState(() => _unsyncedCount = records.length);
  }

  Future<void> _loadTodayAttendance() async {
    setState(() => _loadingAttendance = true);
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final all = await DatabaseService.instance.getAttendanceByDate(today);
      final filtered = _selectedSubjectId != null
          ? all.where((r) => r.subjectId == _selectedSubjectId).toList()
          : all;
      if (mounted) setState(() => _todayAttendance = filtered);
    } finally {
      if (mounted) setState(() => _loadingAttendance = false);
    }
  }

  // ── Start mandatory 5-minute session ─────────────────────────
  // Session CANNOT be stopped manually — only expires automatically
  void _startMandatorySession() {
    _sessionTimer?.cancel();
    _sessionCountdown = sessionDurationSeconds;
    _sessionExpired = false;
    _sessionStarted = true;

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_sessionCountdown > 0) {
        setState(() => _sessionCountdown--);
      } else {
        timer.cancel();
        // Session expired — auto stop server
        _autoStopServer();
      }
    });
  }

  // Auto stop when timer expires (not user-initiated)
  Future<void> _autoStopServer() async {
    _otpTimer?.cancel();

    // Capture session details BEFORE stopping (stopServer clears state)
    final subjectId = _sessionSubjectId;
    final teacherId = _sessionTeacherId;
    final deptId = _sessionDeptId;
    final year = _sessionYear;
    final timeSlot = _sessionTimeSlot;
    final date = _sessionDate;

    await LanServerService.instance.stopServer();

    // Call backend to fill in ABSENT records for students who didn't attend
    if (subjectId != null && teacherId != null && deptId != null &&
        year != null && timeSlot != null && date != null) {
      try {
        await ApiService.instance.finalizeSession(
          subjectId: subjectId,
          teacherId: teacherId,
          departmentId: deptId,
          yearOfStudy: year,
          attendanceDate: date,
          timeSlot: timeSlot,
          presentStudentIds: const [], // backend will diff against all records
        );
      } catch (e) {
        // Non-fatal — backend determines absent from missing PRESENT records
        debugPrint('finalizeSession error (non-fatal): $e');
      }
    }

    if (mounted) {
      setState(() {
        _sessionExpired = true;
        _sessionStarted = false;
        _serverRunning = false;
        _serverIp = null;
        _currentOtp = null;
        _roomCode = null;
        _sessionCountdown = 0;
        // Reset class setup for next session
        _selectedDeptId = null;
        _selectedYear = null;
        _selectedSubjectId = null;
        _selectedSubjectName = null;
        _selectedDeptName = null;
      });
    }
    await _loadUnsyncedCount();
    await _loadTodayAttendance();
    Fluttertoast.showToast(
      msg: '✅ 5-minute session complete! Attendance window closed.',
      backgroundColor: Colors.blue,
      toastLength: Toast.LENGTH_LONG,
    );
  }

  String get _sessionTimeFormatted {
    final m = _sessionCountdown ~/ 60;
    final s = _sessionCountdown % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _sessionColor {
    if (_sessionCountdown > 180) return Colors.green;
    if (_sessionCountdown > 60) return Colors.orange;
    return Colors.red;
  }

  Future<void> _generateOtpAndStartServer() async {
    if (_selectedDeptId == null) {
      Fluttertoast.showToast(msg: 'Please select a department'); return;
    }
    if (_selectedYear == null) {
      Fluttertoast.showToast(msg: 'Please select a year'); return;
    }
    if (_selectedSubjectId == null) {
      Fluttertoast.showToast(msg: 'Please select a subject'); return;
    }
    if (_sessionExpired) {
      Fluttertoast.showToast(msg: 'Session ended. Select new subject to start again.');
      return;
    }

    setState(() => _isGenerating = true);
    try {
      Map<String, dynamic> otpData;
      try {
        otpData = await ApiService.instance
            .generateOtp(_selectedSubjectId!, _selectedTimeSlot);
      } catch (_) {
        otpData = _generateLocalOtp();
      }

      final otp = otpData['otp'] as String;
      final expiresAt = DateTime.parse(otpData['expiresAt'] as String);
      final user = ref.read(currentUserProvider);

      if (!_serverRunning) {
        final ip = await LanServerService.instance.startServer(
          otp: otp,
          expiresAt: expiresAt,
          subjectId: _selectedSubjectId!,
          subjectName: _selectedSubjectName ?? '',
          teacherId: user!.userId,
          timeSlot: _selectedTimeSlot,
        );
        setState(() {
          _serverRunning = true;
          _serverIp = ip;
          _roomCode = LanServerService.instance.roomCode;
        });

        // Snapshot the session parameters — needed for finalizeSession()
        // after the dropdowns are cleared on expiry.
        _sessionSubjectId = _selectedSubjectId;
        _sessionTeacherId = user.userId;
        _sessionDeptId = _selectedDeptId;
        _sessionYear = _selectedYear;
        _sessionTimeSlot = _selectedTimeSlot;
        _sessionDate = DateTime.now().toIso8601String().substring(0, 10);

        // Start mandatory timer — cannot be cancelled by user
        _startMandatorySession();
      } else {
        // Regenerate OTP within session
        LanServerService.instance.updateOtp(otp: otp, expiresAt: expiresAt);
      }

      setState(() { _currentOtp = otp; _otpCountdown = 60; });
      _startOtpCountdown();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Map<String, dynamic> _generateLocalOtp() {
    final otp =
    (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString();
    final expiresAt = DateTime.now().add(const Duration(seconds: 60));
    return {'otp': otp, 'expiresAt': expiresAt.toIso8601String()};
  }

  void _startOtpCountdown() {
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_otpCountdown > 0) {
        setState(() => _otpCountdown--);
        if (_otpCountdown % 5 == 0 && _tabController.index == 1) {
          _loadTodayAttendance();
        }
      } else {
        timer.cancel();
        setState(() => _currentOtp = null);
        _loadUnsyncedCount();
      }
    });
  }

  Future<void> _syncAttendance() async {
    setState(() => _isSyncing = true);
    try {
      final result = await SyncService.instance.syncPendingRecords();
      Fluttertoast.showToast(
        msg: result.message,
        backgroundColor: result.hasError ? Colors.orange : Colors.green,
        toastLength: Toast.LENGTH_LONG,
      );
      await _loadUnsyncedCount();
      await _loadTodayAttendance();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${user?.fullName ?? 'Teacher'}'),
        actions: [
          // Only show logout when session is NOT active
          if (!_serverRunning)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  _sessionTimeFormatted,
                  style: TextStyle(
                    color: _sessionColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(icon: Icon(Icons.lock_open), text: 'OTP Session'),
            Tab(
              icon: Stack(clipBehavior: Clip.none, children: [
                const Icon(Icons.people),
                if (_unsyncedCount > 0)
                  Positioned(
                    right: -4, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: Text('$_unsyncedCount',
                          style: const TextStyle(
                              fontSize: 8, color: Colors.white)),
                    ),
                  ),
              ]),
              text: 'Students Present',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOtpTab(), _buildStudentsTab()],
      ),
    );
  }

  Widget _buildOtpTab() {
    final sessionLocked = _serverRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        _buildServerStatus(),
        const SizedBox(height: 16),

        // Mandatory session timer in body too (when active)
        if (_serverRunning) ...[
          _buildSessionTimerCard(),
          const SizedBox(height: 16),
        ],

        // Class Setup
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Class Setup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              const SizedBox(height: 4),

              _buildDropdown<int>(
                label: 'Department', icon: Icons.domain,
                value: _selectedDeptId,
                hint: 'Select Department',
                enabled: !sessionLocked,
                items: _departments.map<DropdownMenuItem<int>>((d) =>
                    DropdownMenuItem(
                        value: d['id'] as int,
                        child: Text(d['name'] ?? '',
                            overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedDeptId = v;
                    _selectedDeptName = _departments
                        .firstWhere((d) => d['id'] == v,
                        orElse: () => {'name': ''})['name'];
                    _selectedYear = null;
                    _selectedSubjectId = null;
                    _selectedSubjectName = null;
                  });
                  _filterSubjects();
                },
              ),
              const SizedBox(height: 12),

              _buildDropdown<int>(
                label: 'Year of Study', icon: Icons.calendar_today,
                value: _selectedYear,
                hint: 'Select Year',
                enabled: !sessionLocked && _selectedDeptId != null,
                items: [1, 2, 3, 4].map((y) => DropdownMenuItem(
                    value: y, child: Text('Year $y'))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedYear = v;
                    _selectedSubjectId = null;
                    _selectedSubjectName = null;
                  });
                  _filterSubjects();
                },
              ),
              const SizedBox(height: 12),

              _buildDropdown<int>(
                label: 'Subject', icon: Icons.book,
                value: _selectedSubjectId,
                hint: _selectedYear == null ? 'Select year first'
                    : _filteredSubjects.isEmpty ? 'No subjects for selection'
                    : 'Select Subject',
                enabled: !sessionLocked && _selectedYear != null &&
                    _filteredSubjects.isNotEmpty,
                items: _filteredSubjects.map<DropdownMenuItem<int>>((s) =>
                    DropdownMenuItem(
                        value: s['id'] as int,
                        child: Text('${s['name']} (${s['code']})',
                            overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedSubjectId = v;
                    _selectedSubjectName = _filteredSubjects
                        .firstWhere((s) => s['id'] == v,
                        orElse: () => {'name': ''})['name'];
                  });
                },
              ),
              const SizedBox(height: 12),

              _buildDropdown<String>(
                label: 'Time Slot', icon: Icons.schedule,
                value: _selectedTimeSlot,
                hint: 'Select Time Slot',
                enabled: !sessionLocked,
                items: _timeSlots.map((t) =>
                    DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _selectedTimeSlot = v!),
              ),

              // Selection summary
              if (_selectedSubjectId != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade600, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_selectedDeptName • Year $_selectedYear • $_selectedSubjectName • $_selectedTimeSlot',
                        style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // Room Code
        if (_roomCode != null) ...[_buildRoomCodeCard(), const SizedBox(height: 16)],

        // OTP
        if (_currentOtp != null) ...[_buildOtpCard(), const SizedBox(height: 16)],

        // Session expired info
        if (_sessionExpired) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info, color: Colors.blue.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Previous session complete. Select a new subject and time slot to start a new 5-minute session.',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Generate OTP button
        ElevatedButton.icon(
          onPressed: _isGenerating ? null : _generateOtpAndStartServer,
          icon: _isGenerating
              ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.lock_open),
          label: Text(_serverRunning
              ? 'Regenerate OTP'
              : 'Generate OTP & Start 5-Min Session'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),

        // Info: session cannot be stopped manually
        if (_serverRunning) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              '⏱ Session runs for 5 minutes and closes automatically',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ],

        const SizedBox(height: 24),
        _buildSyncCard(),
      ]),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required String hint,
    required bool enabled,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: enabled ? null : Colors.grey.shade400),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        filled: !enabled,
        fillColor: enabled ? null : Colors.grey.shade50,
      ),
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      items: enabled ? items : [],
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _buildSessionTimerCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _sessionColor, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: _sessionColor.withOpacity(0.05),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Icon(Icons.timer, color: _sessionColor, size: 20),
            const SizedBox(width: 8),
            Text('Attendance Window',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _sessionColor,
                    fontSize: 14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _sessionColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _sessionColor),
              ),
              child: Text(
                _sessionTimeFormatted,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _sessionColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _sessionCountdown / sessionDurationSeconds,
              color: _sessionColor,
              backgroundColor: _sessionColor.withOpacity(0.15),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _sessionCountdown > 60
                ? 'Students can mark attendance. Session auto-closes at 00:00'
                : '⚠️ Less than 1 minute! Session closing soon.',
            style: TextStyle(
                fontSize: 12, color: _sessionColor.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  Widget _buildRoomCodeCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.indigo, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.indigo.shade50, Colors.blue.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            Icon(Icons.meeting_room, color: Colors.indigo.shade700, size: 20),
            const SizedBox(width: 8),
            Text('Room Code',
                style: TextStyle(
                    color: Colors.indigo.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.copy, color: Colors.indigo.shade400, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _roomCode!));
                Fluttertoast.showToast(msg: 'Room code copied!');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade200),
              boxShadow: [
                BoxShadow(color: Colors.indigo.withOpacity(0.1),
                    blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Text(_roomCode!,
                style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 16,
                    color: Colors.indigo.shade800)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.indigo.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Students: Enter this code to connect instantly',
              style: TextStyle(
                  color: Colors.indigo.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildOtpCard() {
    final color = _otpCountdown > 20 ? Colors.green
        : _otpCountdown > 10 ? Colors.orange : Colors.red;
    return Card(
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text('Current OTP',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_currentOtp!,
              style: TextStyle(
                  fontSize: 44, fontWeight: FontWeight.bold,
                  letterSpacing: 12, color: color)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: _otpCountdown / 60,
              color: color, backgroundColor: color.withOpacity(0.2)),
          const SizedBox(height: 4),
          Text('Expires in $_otpCountdown seconds',
              style: TextStyle(color: color, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildSyncCard() {
    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.cloud_upload, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text('Sync to Server',
                style: TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 16, color: Colors.blue.shade700)),
            const Spacer(),
            if (_unsyncedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$_unsyncedCount pending',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            if (_unsyncedCount == 0)
              const Icon(Icons.check_circle, color: Colors.green),
          ]),
          const SizedBox(height: 8),
          Text(
            _unsyncedCount > 0
                ? '$_unsyncedCount records not yet synced.'
                : 'All records synced ✓',
            style: TextStyle(color: Colors.blue.shade600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSyncing ? null : _syncAttendance,
              icon: _isSyncing
                  ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
              label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStudentsTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.green.shade50,
        child: Row(children: [
          Icon(Icons.calendar_today, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Text('Today: ${DateTime.now().toIso8601String().substring(0, 10)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.green, borderRadius: BorderRadius.circular(20)),
            child: Text('${_todayAttendance.length} present',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodayAttendance,
            color: Colors.green.shade700,
          ),
        ]),
      ),
      Expanded(
        child: _loadingAttendance
            ? const Center(child: CircularProgressIndicator())
            : _todayAttendance.isEmpty
            ? Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.people_outline,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(_serverRunning
              ? 'Waiting for students...'
              : 'No attendance recorded today',
              style: TextStyle(color: Colors.grey.shade600)),
          if (_roomCode != null) ...[
            const SizedBox(height: 8),
            Text('Room Code: $_roomCode',
                style: TextStyle(
                    color: Colors.indigo.shade600,
                    fontWeight: FontWeight.bold, fontSize: 18)),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadTodayAttendance,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ]))
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _todayAttendance.length,
          itemBuilder: (context, index) {
            final record = _todayAttendance[index];
            // Show student name if available, fallback to ID
            final displayName = record.studentName != null &&
                record.studentName!.isNotEmpty
                ? record.studentName!
                : 'Student #${record.studentId}';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Text('${index + 1}',
                      style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(displayName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold)),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Time: ${record.timeSlot}'),
                      Text('Marked: ${record.markedAt.length > 16 ? record.markedAt.substring(11, 16) : record.markedAt}'),
                    ]),
                trailing: Row(
                    mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(record.status,
                        style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    record.isSynced
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    size: 16,
                    color: record.isSynced
                        ? Colors.green
                        : Colors.orange,
                  ),
                ]),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildServerStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _serverRunning ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: _serverRunning ? Colors.green : Colors.grey.shade300),
      ),
      child: Row(children: [
        Icon(_serverRunning ? Icons.wifi : Icons.wifi_off,
            color: _serverRunning ? Colors.green : Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_serverRunning ? 'LAN Server Active' : 'LAN Server Offline',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _serverRunning
                        ? Colors.green.shade800
                        : Colors.grey)),
            if (_serverIp != null)
              Text('IP: $_serverIp:8181',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _sessionTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
}