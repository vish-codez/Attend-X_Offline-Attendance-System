import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../models/attendance_model.dart';

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});

  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _departments = [];
  List<dynamic> _subjects = [];
  List<AttendanceStats> _stats = [];
  bool _loading = false;
  int? _filterDeptId;
  int? _filterYear;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final depts = await ApiService.instance.getDepartments();
      final subs = await ApiService.instance.getAllSubjects();
      final stats = await ApiService.instance.getAttendanceStats(
        departmentId: _filterDeptId,
        yearOfStudy: _filterYear,
      );
      setState(() {
        _departments = depts;
        _subjects = subs;
        _stats = stats.map((e) => AttendanceStats.fromJson(e)).toList();
      });
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not load data: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _getDeptNameFromSubject(dynamic subject) {
    final dept = subject['department'];
    if (dept == null) return 'No Department';
    return dept['name'] ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Admin Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.person_add, size: 20), text: 'Register'),
            Tab(icon: Icon(Icons.book, size: 20), text: 'Subjects'),
            Tab(icon: Icon(Icons.bar_chart, size: 20), text: 'Attendance'),
            Tab(icon: Icon(Icons.settings, size: 20), text: 'Manage'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRegisterTab(),
          _buildSubjectsTab(),
          _buildAttendanceTab(),
          _buildManageTab(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 1: Register
  // ══════════════════════════════════════════════════════════════
  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 8),
        _buildActionCard(
          icon: Icons.person_add, title: 'Register Teacher',
          subtitle: 'Add a new teacher account with department',
          color: Colors.blue, onTap: _showRegisterTeacherDialog,
        ),
        const SizedBox(height: 12),
        _buildActionCard(
          icon: Icons.school, title: 'Register Student',
          subtitle: 'Add a new student with roll number and section',
          color: Colors.green, onTap: _showRegisterStudentDialog,
        ),
        const SizedBox(height: 12),
        _buildActionCard(
          icon: Icons.lock_reset, title: 'Reset Password',
          subtitle: 'Reset password for any teacher or student',
          color: Colors.orange, onTap: _showResetPasswordDialog,
        ),
      ]),
    );
  }

  Widget _buildActionCard({
    required IconData icon, required String title,
    required String subtitle, required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 12)),
              ]),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  void _showRegisterTeacherDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final empIdCtrl = TextEditingController();
    int? selectedDeptId;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogHeader('Register Teacher', Icons.person_add, Colors.blue),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _formField(nameCtrl, 'Full Name', Icons.badge,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _formField(usernameCtrl, 'Username', Icons.person,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _formField(emailCtrl, 'Email', Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _formField(empIdCtrl, 'Employee ID', Icons.badge_outlined),
                  const SizedBox(height: 12),
                  _deptDropdown(
                    value: selectedDeptId,
                    onChanged: (v) => setDialogState(() => selectedDeptId = v),
                    validator: (v) => v == null ? 'Select department' : null,
                  ),
                ]),
              ),
            ),
            _dialogButtons(
              ctx: ctx,
              color: Colors.blue,
              onConfirm: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  await ApiService.instance.registerTeacher({
                    'username': usernameCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'fullName': nameCtrl.text.trim(),
                    'employeeId': empIdCtrl.text.trim(),
                    'departmentId': selectedDeptId,
                    'password': 'Teacher@123',
                  });
                  Fluttertoast.showToast(
                      msg: '✅ Teacher registered!\nDefault password: Teacher@123',
                      backgroundColor: Colors.green,
                      toastLength: Toast.LENGTH_LONG);
                } catch (e) {
                  Fluttertoast.showToast(msg: 'Error: $e', backgroundColor: Colors.red);
                }
              },
              confirmLabel: 'Register',
            ),
          ]),
        ),
      ),
    );
  }

  void _showRegisterStudentDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final rollCtrl = TextEditingController();
    int? selectedDeptId;
    int selectedYear = 1;
    String selectedSection = 'A';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogHeader('Register Student', Icons.school, Colors.green),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _formField(nameCtrl, 'Full Name', Icons.badge,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null),
                    const SizedBox(height: 12),
                    _formField(usernameCtrl, 'Username', Icons.person,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null),
                    const SizedBox(height: 12),
                    _formField(emailCtrl, 'Email', Icons.email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null),
                    const SizedBox(height: 12),
                    _formField(rollCtrl, 'Roll Number', Icons.numbers,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null),
                    const SizedBox(height: 12),
                    _deptDropdown(
                      value: selectedDeptId,
                      onChanged: (v) => setDialogState(() => selectedDeptId = v),
                      validator: (v) => v == null ? 'Select department' : null,
                    ),
                    const SizedBox(height: 12),
                    _styledDropdown<int>(
                      value: selectedYear, label: 'Year of Study',
                      icon: Icons.calendar_today,
                      items: [1, 2, 3, 4].map((y) => DropdownMenuItem(
                          value: y, child: Text('Year $y'))).toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedYear = v ?? 1),
                    ),
                    const SizedBox(height: 12),
                    _styledDropdown<String>(
                      value: selectedSection, label: 'Section',
                      icon: Icons.group,
                      items: ['A', 'B', 'C', 'D'].map((s) => DropdownMenuItem(
                          value: s, child: Text('Section $s'))).toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedSection = v ?? 'A'),
                    ),
                  ]),
                ),
              ),
              _dialogButtons(
                ctx: ctx,
                color: Colors.green,
                onConfirm: () async {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(ctx);
                  try {
                    await ApiService.instance.registerStudent({
                      'username': usernameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'fullName': nameCtrl.text.trim(),
                      'rollNumber': rollCtrl.text.trim(),
                      'departmentId': selectedDeptId,
                      'yearOfStudy': selectedYear,
                      'section': selectedSection,
                      'password': 'Student@123',
                    });
                    Fluttertoast.showToast(
                        msg: '✅ Student registered!\nDefault password: Student@123',
                        backgroundColor: Colors.green,
                        toastLength: Toast.LENGTH_LONG);
                  } catch (e) {
                    Fluttertoast.showToast(msg: 'Error: $e', backgroundColor: Colors.red);
                  }
                },
                confirmLabel: 'Register',
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showResetPasswordDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogHeader('Reset Password', Icons.lock_reset, Colors.orange),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _formField(usernameCtrl, 'Username', Icons.person,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) =>
                    (v?.length ?? 0) < 6 ? 'Min 6 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    validator: (v) =>
                    v != passwordCtrl.text ? 'Passwords do not match' : null,
                  ),
                ]),
              ),
            ),
            _dialogButtons(
              ctx: ctx,
              color: Colors.orange,
              onConfirm: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  await ApiService.instance.resetPassword(
                      usernameCtrl.text.trim(), passwordCtrl.text.trim());
                  Fluttertoast.showToast(
                      msg: '✅ Password reset successfully',
                      backgroundColor: Colors.green);
                } catch (e) {
                  Fluttertoast.showToast(
                      msg: 'Error: $e', backgroundColor: Colors.red);
                }
              },
              confirmLabel: 'Reset',
            ),
          ]),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 2: Subjects
  // ══════════════════════════════════════════════════════════════
  Widget _buildSubjectsTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Text('Subjects',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showCreateSubjectDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Subject'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      ),
      Expanded(
        child: _subjects.isEmpty
            ? Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('No subjects yet',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              ElevatedButton(
                  onPressed: _showCreateSubjectDialog,
                  child: const Text('Add First Subject')),
            ]))
            : ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _subjects.length,
          itemBuilder: (ctx, i) {
            final s = _subjects[i];
            final deptName = _getDeptNameFromSubject(s);
            final year = s['yearOfStudy'] ?? '-';
            final credits = s['credits'] ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.book,
                      color: Colors.blue.shade600, size: 22),
                ),
                title: Text('${s['name']} (${s['code']})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    _pill(deptName, Colors.blue),
                    const SizedBox(width: 6),
                    _pill('Year $year', Colors.green),
                  ]),
                ),
                trailing: _pill('$credits cr', Colors.orange),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _pill(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200),
      ),
      child: Text(text,
          style: TextStyle(
              color: color.shade700, fontSize: 11,
              fontWeight: FontWeight.w500)),
    );
  }

  void _showCreateSubjectDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final creditsCtrl = TextEditingController(text: '3');
    int? selectedDeptId;
    int selectedYear = 1;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogHeader('Create Subject', Icons.book, Colors.indigo),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _formField(nameCtrl, 'Subject Name', Icons.book,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _formField(codeCtrl, 'Subject Code (e.g. CS301)', Icons.code,
                      validator: (v) => v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _deptDropdown(
                    value: selectedDeptId,
                    onChanged: (v) => setDialogState(() => selectedDeptId = v),
                    validator: (v) => v == null ? 'Select department' : null,
                  ),
                  const SizedBox(height: 12),
                  _styledDropdown<int>(
                    value: selectedYear, label: 'Year of Study',
                    icon: Icons.calendar_today,
                    items: [1, 2, 3, 4].map((y) => DropdownMenuItem(
                        value: y, child: Text('Year $y'))).toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedYear = v ?? 1),
                  ),
                  const SizedBox(height: 12),
                  _formField(creditsCtrl, 'Credits', Icons.star,
                      keyboardType: TextInputType.number),
                ]),
              ),
            ),
            _dialogButtons(
              ctx: ctx,
              color: Colors.indigo,
              onConfirm: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  await ApiService.instance.createSubject(
                    name: nameCtrl.text.trim(),
                    code: codeCtrl.text.trim(),
                    departmentId: selectedDeptId!,
                    yearOfStudy: selectedYear,
                    credits: int.tryParse(creditsCtrl.text.trim()) ?? 3,
                  );
                  Fluttertoast.showToast(
                      msg: '✅ Subject created!', backgroundColor: Colors.green);
                  _loadData();
                } catch (e) {
                  Fluttertoast.showToast(
                      msg: 'Error: $e', backgroundColor: Colors.red);
                }
              },
              confirmLabel: 'Create',
            ),
          ]),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 3: Attendance
  // ══════════════════════════════════════════════════════════════
  Widget _buildAttendanceTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(children: [
          Expanded(
            child: _styledDropdown<int>(
              value: _filterDeptId, label: 'Department', icon: Icons.domain,
              items: [
                const DropdownMenuItem(value: null, child: Text('All Depts')),
                ..._departments.map<DropdownMenuItem<int>>((d) =>
                    DropdownMenuItem(
                        value: d['id'] as int, child: Text(d['name']))),
              ],
              onChanged: (v) { setState(() => _filterDeptId = v); _loadData(); },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _styledDropdown<int>(
              value: _filterYear, label: 'Year', icon: Icons.calendar_today,
              items: [
                const DropdownMenuItem(value: null, child: Text('All Years')),
                ...[1, 2, 3, 4].map((y) => DropdownMenuItem(
                    value: y, child: Text('Year $y'))),
              ],
              onChanged: (v) { setState(() => _filterYear = v); _loadData(); },
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isDownloading ? null : _downloadExcel,
            icon: _isDownloading
                ? const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download, size: 16),
            label: const Text('Excel'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _stats.isEmpty
            ? Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('No attendance data',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _loadData, child: const Text('Refresh')),
            ]))
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _stats.length,
          itemBuilder: (ctx, i) {
            final s = _stats[i];
            final color =
            s.percentage >= 75 ? Colors.green : Colors.red;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Text('${s.percentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: color, fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(s.studentName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('${s.subjectName} • ${s.rollNumber}',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
                trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${s.presentCount}/${s.totalClasses}',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.bold)),
                      Text('classes',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 10)),
                    ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── Save Excel to public Downloads folder ─────────────────────
  Future<void> _downloadExcel() async {
    setState(() => _isDownloading = true);
    try {
      Fluttertoast.showToast(msg: '⏳ Generating Excel report...');
      final bytes = await ApiService.instance.exportAttendanceExcel(
        departmentId: _filterDeptId,
        yearOfStudy: _filterYear,
      );

      // Save directly to public Downloads folder
      final fileName =
          'attendance_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      // Try public Downloads first
      File? savedFile;
      final downloadPaths = [
        '/storage/emulated/0/Download/$fileName',
        '/storage/emulated/0/Downloads/$fileName',
        '/sdcard/Download/$fileName',
      ];

      for (final path in downloadPaths) {
        try {
          final dir = Directory(path.substring(0, path.lastIndexOf('/')));
          if (await dir.exists()) {
            final file = File(path);
            await file.writeAsBytes(bytes);
            savedFile = file;
            break;
          }
        } catch (_) {}
      }

      // Fallback to external storage if none worked
      if (savedFile == null) {
        // Create Downloads directory manually if it doesn't exist
        const basePath = '/storage/emulated/0/Download';
        try {
          final dir = Directory(basePath);
          if (!await dir.exists()) await dir.create(recursive: true);
          final file = File('$basePath/$fileName');
          await file.writeAsBytes(bytes);
          savedFile = file;
        } catch (_) {
          // Last resort: app documents directory
          final file = File(
              '/data/data/${await _getPackageName()}/files/$fileName');
          await file.writeAsBytes(bytes);
          savedFile = file;
        }
      }

      if (savedFile != null && await savedFile.exists()) {
        Fluttertoast.showToast(
          msg: '✅ Excel saved to Downloads!\nFile: $fileName',
          backgroundColor: Colors.green,
          toastLength: Toast.LENGTH_LONG,
        );
      } else {
        Fluttertoast.showToast(
          msg: '❌ Could not save file. Check storage permission.',
          backgroundColor: Colors.red,
          toastLength: Toast.LENGTH_LONG,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
          msg: 'Export failed: $e', backgroundColor: Colors.red);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<String> _getPackageName() async {
    return 'com.attendance.app';
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 4: Manage
  // ══════════════════════════════════════════════════════════════
  Widget _buildManageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildActionCard(
          icon: Icons.domain, title: 'Add Department',
          subtitle: 'Create a new college department',
          color: Colors.purple, onTap: _showAddDepartmentDialog,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.domain, color: Colors.purple.shade700, size: 20),
                const SizedBox(width: 8),
                Text('Departments (${_departments.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ]),
            ),
            const Divider(height: 1),
            ..._departments.map((d) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.purple.shade50,
                child: Text(
                  (d['code'] ?? '?').toString().isNotEmpty
                      ? (d['code'] ?? '?').toString()[0]
                      : '?',
                  style: TextStyle(color: Colors.purple.shade700,
                      fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(d['name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(d['code'] ?? ''),
              dense: true,
            )),
            if (_departments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('No departments yet',
                    style: TextStyle(color: Colors.grey))),
              ),
          ]),
        ),
      ]),
    );
  }

  void _showAddDepartmentDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _dialogHeader('Add Department', Icons.domain, Colors.purple),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _formField(nameCtrl, 'Department Name', Icons.domain,
                    validator: (v) => v?.isEmpty == true ? 'Required' : null),
                const SizedBox(height: 12),
                _formField(codeCtrl, 'Code (e.g. CSE)', Icons.code,
                    validator: (v) => v?.isEmpty == true ? 'Required' : null),
              ]),
            ),
          ),
          _dialogButtons(
            ctx: ctx,
            color: Colors.purple,
            onConfirm: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              try {
                await ApiService.instance.createDepartment(
                    nameCtrl.text.trim(), codeCtrl.text.trim());
                Fluttertoast.showToast(
                    msg: '✅ Department created!', backgroundColor: Colors.green);
                _loadData();
              } catch (e) {
                Fluttertoast.showToast(
                    msg: 'Error: $e', backgroundColor: Colors.red);
              }
            },
            confirmLabel: 'Create',
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Shared UI helpers
  // ══════════════════════════════════════════════════════════════
  Widget _dialogHeader(String title, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
      ]),
    );
  }

  Widget _dialogButtons({
    required BuildContext ctx,
    required Color color,
    required VoidCallback onConfirm,
    required String confirmLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12)),
            child: Text(confirmLabel),
          ),
        ),
      ]),
    );
  }

  Widget _formField(
      TextEditingController ctrl, String label, IconData icon, {
        TextInputType? keyboardType,
        String? Function(String?)? validator,
      }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _deptDropdown({
    required int? value,
    required void Function(int?) onChanged,
    String? Function(int?)? validator,
  }) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Department',
        prefixIcon: const Icon(Icons.domain),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 14),
      ),
      hint: const Text('Select Department'),
      items: _departments.map<DropdownMenuItem<int>>((d) {
        return DropdownMenuItem<int>(
          value: d['id'] as int,
          child: Text(d['name'] ?? '', overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _styledDropdown<T>({
    required T? value, required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 14),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}