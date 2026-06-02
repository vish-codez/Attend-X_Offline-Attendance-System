import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  static const String _tokenKey = 'jwt_token';
  static const String _baseUrlKey = 'base_url';
  static const String _defaultBaseUrl = 'http://192.168.1.1:8080';

  final _storage = const FlutterSecureStorage(
    // Use EncryptedSharedPreferences on Android — much faster than Keystore
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  late Dio _dio;

  // ── In-memory cache — read from storage ONCE at init, never again ──────
  String _cachedToken = '';
  String _cachedBaseUrl = _defaultBaseUrl;

  Future<void> init() async {
    // Read both values in parallel — only storage reads happen here
    final results = await Future.wait([
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _tokenKey),
    ]);
    _cachedBaseUrl = results[0] ?? _defaultBaseUrl;
    _cachedToken   = results[1] ?? '';

    _dio = Dio(BaseOptions(
      baseUrl: _cachedBaseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Use cached token — NO async storage read on every request
        if (_cachedToken.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_cachedToken';
        }
        return handler.next(options);
      },
      onError: (error, handler) => handler.next(error),
    ));
  }

  Future<void> setBaseUrl(String url) async {
    _cachedBaseUrl = url;
    _dio.options.baseUrl = url;
    // Write to storage in background — don't await
    _storage.write(key: _baseUrlKey, value: url);
  }

  Future<String?> getBaseUrl() async => _cachedBaseUrl;

  String get activeBaseUrl => _cachedBaseUrl;

  Future<void> updateServerIp(String teacherIp) async {
    await setBaseUrl('http://$teacherIp:8080');
  }

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = '';
    _cachedBaseUrl = _defaultBaseUrl;
    _dio.options.baseUrl = _defaultBaseUrl;
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _baseUrlKey),
    ]);
  }

  // ── Auth ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/api/auth/login',
        data: {'username': username, 'password': password});
    return response.data['data'];
  }

  // ── Teacher ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> generateOtp(int subjectId, String timeSlot) async {
    final response = await _dio.post('/api/teacher/otp/generate',
        data: {'subjectId': subjectId, 'timeSlot': timeSlot});
    return response.data['data'];
  }

  Future<List<dynamic>> getSubjects({int? departmentId, int? yearOfStudy}) async {
    final params = <String, dynamic>{};
    if (departmentId != null) params['departmentId'] = departmentId;
    if (yearOfStudy != null) params['yearOfStudy'] = yearOfStudy;
    final response = await _dio.get('/api/teacher/subjects', queryParameters: params);
    return response.data['data'];
  }

  // ── Student ───────────────────────────────────────────────────
  Future<List<dynamic>> getMyAttendance() async {
    final response = await _dio.get('/api/student/attendance');
    final data = response.data['data'];
    if (data == null) return [];
    return data as List<dynamic>;
  }

  // ── Sync ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> syncAttendance(List<Map<String, dynamic>> records) async {
    final response = await _dio.post('/api/sync/attendance', data: {'records': records});
    return response.data['data'];
  }

  Future<void> finalizeSession({
    required int subjectId,
    required int teacherId,
    required int departmentId,
    required int yearOfStudy,
    required String attendanceDate,
    required String timeSlot,
    required List<int> presentStudentIds,
  }) async {
    await _dio.post('/api/sync/finalize-session', data: {
      'subjectId': subjectId,
      'teacherId': teacherId,
      'departmentId': departmentId,
      'yearOfStudy': yearOfStudy,
      'attendanceDate': attendanceDate,
      'timeSlot': timeSlot,
      'presentStudentIds': presentStudentIds,
    });
  }

  // ── Admin — Register ──────────────────────────────────────────
  Future<Map<String, dynamic>> registerTeacher(Map<String, dynamic> data) async {
    final response = await _dio.post('/api/admin/teachers', data: data);
    return response.data['data'];
  }

  Future<Map<String, dynamic>> registerStudent(Map<String, dynamic> data) async {
    final response = await _dio.post('/api/admin/students', data: data);
    return response.data['data'];
  }

  // ── Admin — Departments ───────────────────────────────────────
  Future<List<dynamic>> getDepartments() async {
    final response = await _dio.get('/api/admin/departments');
    return response.data['data'];
  }

  Future<Map<String, dynamic>> createDepartment(String name, String code) async {
    final response = await _dio.post('/api/admin/departments',
        data: {'name': name, 'code': code});
    return response.data['data'];
  }

  // ── Admin — Subjects ──────────────────────────────────────────
  Future<List<dynamic>> getAllSubjects() async {
    final response = await _dio.get('/api/admin/subjects');
    return response.data['data'];
  }

  Future<Map<String, dynamic>> createSubject({
    required String name,
    required String code,
    required int departmentId,
    required int yearOfStudy,
    int credits = 3,
  }) async {
    final response = await _dio.post('/api/admin/subjects', data: {
      'name': name, 'code': code,
      'departmentId': departmentId,
      'yearOfStudy': yearOfStudy,
      'credits': credits,
    });
    return response.data['data'];
  }

  // ── Admin — Attendance Stats ──────────────────────────────────
  Future<List<dynamic>> getAttendanceStats({
    int? studentId, int? subjectId, int? departmentId, int? yearOfStudy,
  }) async {
    final params = <String, dynamic>{};
    if (studentId != null)    params['studentId']    = studentId;
    if (subjectId != null)    params['subjectId']    = subjectId;
    if (departmentId != null) params['departmentId'] = departmentId;
    if (yearOfStudy != null)  params['yearOfStudy']  = yearOfStudy;
    final response = await _dio.get('/api/admin/attendance/stats', queryParameters: params);
    return response.data['data'];
  }

  // ── Admin — Excel Export ──────────────────────────────────────
  Future<List<int>> exportAttendanceExcel({int? departmentId, int? yearOfStudy}) async {
    final params = <String, dynamic>{};
    if (departmentId != null) params['departmentId'] = departmentId;
    if (yearOfStudy != null)  params['yearOfStudy']  = yearOfStudy;
    final response = await _dio.get(
      '/api/admin/attendance/export',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data as List<int>;
  }

  // ── Admin — Password Reset ────────────────────────────────────
  Future<void> resetPassword(String username, String newPassword) async {
    await _dio.post('/api/admin/reset-password',
        data: {'username': username, 'newPassword': newPassword});
  }

  // ── Admin — List Teachers & Students ─────────────────────────
  Future<List<dynamic>> getTeachers() async {
    final response = await _dio.get('/api/admin/teachers');
    return response.data['data'];
  }

  Future<List<dynamic>> getStudents({int? departmentId, int? yearOfStudy}) async {
    final params = <String, dynamic>{};
    if (departmentId != null) params['departmentId'] = departmentId;
    if (yearOfStudy != null)  params['yearOfStudy']  = yearOfStudy;
    final response = await _dio.get('/api/admin/students', queryParameters: params);
    return response.data['data'];
  }
}