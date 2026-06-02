import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../services/lan_client_service.dart';
import '../../database/database_service.dart';
import '../../models/attendance_model.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _roomCodeController = TextEditingController();
  final _teacherIpController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isConnecting = false;
  bool _isScanning = false;
  bool _isSubmitting = false;
  bool _connected = false;
  bool _useRoomCode = true;
  Map<String, dynamic>? _sessionInfo;

  // My Attendance — purely local SQLite, no network needed
  List<AttendanceRecord> _localRecords = [];
  // Grouped stats computed from local records: subjectId -> _SubjectStat
  List<_SubjectStat> _subjectStats = [];
  bool _loadingStats = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _loadLocalAttendance();
      }
    });
  }

  // ── Load attendance purely from local SQLite ──────────────────────────────
  // No network call, no server URL, no timeout — always works offline.
  Future<void> _loadLocalAttendance() async {
    if (_loadingStats) return;
    if (mounted) setState(() => _loadingStats = true);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final records =
      await DatabaseService.instance.getAttendanceByStudent(user.userId);
      final stats = _computeSubjectStats(records);

      if (mounted) {
        setState(() {
          _localRecords = records;
          _subjectStats = stats;
          _loadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // Group local records by subject and compute present/total counts.
  // "Total" = number of distinct dates this subject was held (from local records).
  // This is purely based on what the student has locally — no backend needed.
  List<_SubjectStat> _computeSubjectStats(List<AttendanceRecord> records) {
    final Map<int, _SubjectStat> map = {};
    for (final r in records) {
      map.putIfAbsent(
        r.subjectId,
            () => _SubjectStat(
          subjectId: r.subjectId,
          subjectName: r.subjectName ?? 'Subject #${r.subjectId}',
        ),
      );
      final stat = map[r.subjectId]!;
      // Count unique date+timeSlot as one class
      final classKey = '${r.attendanceDate}|${r.timeSlot}';
      stat.classDates.add(classKey);
      if (r.status == 'PRESENT') {
        stat.presentDates.add(classKey);
      }
    }
    return map.values.toList()
      ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
  }

  // ── Teacher connection (for OTP marking only) ─────────────────────────────
  Future<void> _connectByRoomCode() async {
    final code = _roomCodeController.text.trim();
    if (code.length != 4) {
      Fluttertoast.showToast(msg: 'Enter 4-digit room code');
      return;
    }
    setState(() => _isScanning = true);
    try {
      final myIp = await NetworkInfo().getWifiIP() ?? '';
      if (myIp.isEmpty) {
        Fluttertoast.showToast(msg: 'Not connected to WiFi');
        return;
      }
      Fluttertoast.showToast(msg: 'Searching for room $code...');
      final teacherIp =
      await LanClientService.instance.findByRoomCode(myIp, code);
      if (teacherIp != null) {
        await _connectToTeacher(teacherIp);
      } else {
        Fluttertoast.showToast(
            msg: 'Room $code not found. Make sure teacher started session.',
            toastLength: Toast.LENGTH_LONG);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _autoDiscoverTeacher() async {
    setState(() => _isScanning = true);
    final myIp = await NetworkInfo().getWifiIP() ?? '';
    if (myIp.isEmpty) {
      Fluttertoast.showToast(msg: 'Not connected to WiFi');
      setState(() => _isScanning = false);
      return;
    }
    final teacherIp = await LanClientService.instance.discoverTeacher(myIp);
    if (teacherIp != null) {
      _teacherIpController.text = teacherIp;
      await _connectToTeacher(teacherIp);
    } else {
      Fluttertoast.showToast(msg: 'Teacher not found. Enter IP manually.');
    }
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connectToTeacher(String ip) async {
    if (ip.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter teacher IP');
      return;
    }
    setState(() => _isConnecting = true);
    try {
      LanClientService.instance.setTeacherIp(ip);
      final ping = await LanClientService.instance.pingTeacher(ip);
      if (!ping) {
        Fluttertoast.showToast(msg: 'Cannot reach teacher at $ip:8181');
        if (mounted) setState(() => _connected = false);
        return;
      }
      final info = await LanClientService.instance.getSessionInfo();
      if (mounted) setState(() { _connected = true; _sessionInfo = info; });
      Fluttertoast.showToast(msg: '✅ Connected!', backgroundColor: Colors.green);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _markAttendance() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      Fluttertoast.showToast(msg: 'Enter 6-digit OTP');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final user = ref.read(currentUserProvider)!;
      final result = await LanClientService.instance.submitOtp(
        otp: otp,
        studentId: user.userId,
        studentName: user.fullName,
      );
      if (result['success'] == true) {
        // ── KEY FIX ──────────────────────────────────────────────────────────
        // The teacher's server saves the record to the TEACHER's SQLite.
        // We must also save it to the STUDENT's own SQLite so My Attendance
        // can show it without needing any network connection.
        try {
          final info = _sessionInfo;
          final subjectId   = info?['subjectId']   as int?;
          final subjectName = info?['subjectName']  as String?;
          final timeSlot    = info?['timeSlot']     as String?;
          final today = DateTime.now().toIso8601String().substring(0, 10);

          if (subjectId != null && timeSlot != null) {
            final record = AttendanceRecord(
              studentId:      user.userId,
              studentName:    user.fullName,
              subjectId:      subjectId,
              subjectName:    subjectName ?? 'Subject #$subjectId',
              teacherId:      0,
              attendanceDate: today,
              timeSlot:       timeSlot,
              status:         'PRESENT',
              markedAt:       DateTime.now().toIso8601String(),
              isSynced:       false,
            );
            await DatabaseService.instance.insertAttendance(record);
          }
        } catch (_) {
          // Non-fatal — record already saved on teacher side
        }
        // ─────────────────────────────────────────────────────────────────────

        Fluttertoast.showToast(
            msg: '✅ Attendance marked!',
            backgroundColor: Colors.green,
            toastLength: Toast.LENGTH_LONG);
        _otpController.clear();
        // Switch to My Attendance tab — will now show the record just saved
        _tabController.animateTo(1);
        await _loadLocalAttendance();
      } else {
        Fluttertoast.showToast(
            msg: '❌ ${result['error'] ?? 'Failed'}',
            backgroundColor: Colors.red,
            toastLength: Toast.LENGTH_LONG);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user?.fullName ?? 'Student',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (user?.departmentName != null || user?.yearOfStudy != null)
              Row(children: [
                if (user?.departmentName != null) ...[
                  const Icon(Icons.domain, size: 11, color: Colors.white70),
                  const SizedBox(width: 3),
                  Text(user!.departmentName!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70)),
                ],
                if (user?.departmentName != null && user?.yearOfStudy != null)
                  const Text('  •  ',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                if (user?.yearOfStudy != null) ...[
                  const Icon(Icons.school, size: 11, color: Colors.white70),
                  const SizedBox(width: 3),
                  Text('Year ${user!.yearOfStudy}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70)),
                ],
                if (user?.section != null) ...[
                  const Text('  •  ',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                  Text('Sec ${user!.section}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70)),
                ],
              ]),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout()),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.how_to_reg), text: 'Mark Attendance'),
            Tab(icon: Icon(Icons.bar_chart), text: 'My Attendance'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOtpTab(), _buildAttendanceTab()],
      ),
    );
  }

  // ── Mark Attendance Tab ───────────────────────────────────────────────────
  Widget _buildOtpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _connected ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _connected ? Colors.green : Colors.grey.shade300),
              ),
              child: Row(children: [
                Icon(_connected ? Icons.wifi : Icons.wifi_off,
                    color: _connected ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                Text(
                    _connected ? 'Connected to Teacher' : 'Not Connected',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _connected ? Colors.green : Colors.grey)),
              ]),
            ),
            const SizedBox(height: 16),

            // Connection card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Connect to Teacher',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _modeBtn('Room Code',
                            Icons.meeting_room, _useRoomCode,
                                () => setState(() => _useRoomCode = true))),
                        const SizedBox(width: 8),
                        Expanded(child: _modeBtn('Manual IP',
                            Icons.computer, !_useRoomCode,
                                () => setState(() => _useRoomCode = false))),
                      ]),
                      const SizedBox(height: 16),

                      if (_useRoomCode) ...[
                        TextField(
                          controller: _roomCodeController,
                          decoration: const InputDecoration(
                            labelText: '4-Digit Room Code',
                            hintText: 'e.g. 2301',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.meeting_room),
                            counterText: '',
                          ),
                          maxLength: 4,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 32,
                              letterSpacing: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isScanning ? null : _connectByRoomCode,
                            icon: _isScanning
                                ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.meeting_room),
                            label: Text(
                                _isScanning ? 'Searching...' : 'Find & Connect'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            'Ask your teacher for the 4-digit room code',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ),
                      ],

                      if (!_useRoomCode) ...[
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _teacherIpController,
                              decoration: const InputDecoration(
                                labelText: "Teacher's IP",
                                hintText: '192.168.x.x',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.computer),
                              ),
                              keyboardType: TextInputType.url,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isConnecting
                                ? null
                                : () => _connectToTeacher(
                                _teacherIpController.text.trim()),
                            child: _isConnecting
                                ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                                : const Text('Connect'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _isScanning ? null : _autoDiscoverTeacher,
                          icon: _isScanning
                              ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                              : const Icon(Icons.search),
                          label: Text(_isScanning
                              ? 'Scanning...'
                              : 'Auto-Discover Teacher'),
                        ),
                      ],
                    ]),
              ),
            ),

            if (_sessionInfo != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200)),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Session Active',
                            style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.bold)),
                        Text('Time: ${_sessionInfo!['timeSlot'] ?? '-'}',
                            style: TextStyle(
                                color: Colors.blue.shade600, fontSize: 12)),
                        if (_sessionInfo!['roomCode'] != null)
                          Text('Room: ${_sessionInfo!['roomCode']}',
                              style: TextStyle(
                                  color: Colors.indigo.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                      ]),
                ]),
              ),
            ],

            const SizedBox(height: 16),

            // OTP card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  const Text('Enter OTP',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpController,
                    decoration: const InputDecoration(
                        labelText: '6-Digit OTP',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.vpn_key),
                        counterText: ''),
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 28,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                      (_connected && !_isSubmitting) ? _markAttendance : null,
                      icon: _isSubmitting
                          ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle),
                      label: Text(
                          _isSubmitting ? 'Marking...' : 'Mark My Attendance',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  if (!_connected)
                    const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Connect to teacher first',
                            style: TextStyle(
                                color: Colors.red, fontSize: 12))),
                ]),
              ),
            ),
          ]),
    );
  }

  Widget _modeBtn(
      String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.indigo : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: active ? Colors.white : Colors.grey),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ]),
      ),
    );
  }

  // ── My Attendance Tab — 100% local SQLite, zero network ───────────────────
  Widget _buildAttendanceTab() {
    return RefreshIndicator(
      onRefresh: () async => _loadLocalAttendance(),
      child: _buildAttendanceContent(),
    );
  }

  Widget _buildAttendanceContent() {
    if (_loadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show grouped subject stats if we have records
    if (_subjectStats.isNotEmpty) {
      return Column(children: [
        // Banner — local data, no server needed
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.blue.shade50,
          child: Row(children: [
            Icon(Icons.storage, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text('Your attendance records',
                style: TextStyle(
                    fontSize: 12, color: Colors.blue.shade700)),
            const Spacer(),
            TextButton(
              onPressed: _loadLocalAttendance,
              style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              child: const Text('Refresh', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _subjectStats.length,
            itemBuilder: (context, index) {
              final stat = _subjectStats[index];
              final pct = stat.percentage;
              final color = pct >= 75 ? Colors.green : Colors.red;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(stat.subjectName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: color)),
                                child: Text(
                                    '${pct.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ]),
                        const SizedBox(height: 6),
                        Text(
                            '${stat.presentCount} / ${stat.totalCount} classes attended',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: stat.totalCount > 0
                              ? stat.presentCount / stat.totalCount
                              : 0,
                          color: color,
                          backgroundColor: color.withOpacity(0.1),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        if (pct < 75) ...[
                          const SizedBox(height: 6),
                          Text(
                            '⚠️ Below 75% — ${_classesNeeded(stat)} more classes needed',
                            style: TextStyle(
                                color: Colors.red.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ]),
                ),
              );
            },
          ),
        ),
      ]);
    }

    // Empty state
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.bar_chart_outlined,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No attendance records yet',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
              'Mark attendance in the OTP tab\nwhen your teacher starts a session',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadLocalAttendance,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white),
          ),
        ]),
      ],
    );
  }

  int _classesNeeded(_SubjectStat stat) {
    if (stat.totalCount == 0) return 0;
    int needed = 0;
    int present = stat.presentCount;
    int total = stat.totalCount;
    while (present / (total + needed) * 100 < 75) {
      needed++;
    }
    return needed;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomCodeController.dispose();
    _teacherIpController.dispose();
    _otpController.dispose();
    super.dispose();
  }
}

// ── Local stat model — computed from SQLite, no backend needed ───────────────
class _SubjectStat {
  final int subjectId;
  final String subjectName;
  final Set<String> classDates = {};   // all date+slot keys
  final Set<String> presentDates = {}; // present date+slot keys

  _SubjectStat({required this.subjectId, required this.subjectName});

  int get totalCount => classDates.length;
  int get presentCount => presentDates.length;
  double get percentage =>
      totalCount == 0 ? 0 : (presentCount / totalCount) * 100;
}