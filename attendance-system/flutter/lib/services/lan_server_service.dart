import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../database/database_service.dart';
import '../models/attendance_model.dart';

class LanServerService {
  LanServerService._internal();
  static final LanServerService instance = LanServerService._internal();

  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  static const int lanPort = 8181;
  static const int udpPort = 8182;

  String? _currentOtp;
  DateTime? _otpExpiresAt;
  int? _currentSubjectId;
  String? _currentSubjectName;
  int? _currentTeacherId;
  String? _currentTimeSlot;
  String? _roomCode;
  String? _serverIp;

  // Tracks which students marked PRESENT during this session.
  // Used by the teacher dashboard to call finalizeSession() on expiry.
  final List<int> _presentStudentIds = [];

  String? get serverIp => _serverIp;
  bool get isRunning => _server != null;
  String? get roomCode => _roomCode;

  /// Returns a copy of the present student IDs collected this session.
  List<int> get presentStudentIds => List.unmodifiable(_presentStudentIds);

  // Expose session details so the teacher dashboard can call finalizeSession()
  int? get currentSubjectId => _currentSubjectId;
  int? get currentTeacherId => _currentTeacherId;
  String? get currentTimeSlot => _currentTimeSlot;

  String _generateRoomCode() {
    final random = Random();
    return (1000 + random.nextInt(9000)).toString();
  }

  Future<String?> startServer({
    required String otp,
    required DateTime expiresAt,
    required int subjectId,
    required String subjectName,
    required int teacherId,
    required String timeSlot,
  }) async {
    _currentOtp = otp;
    _otpExpiresAt = expiresAt;
    _currentSubjectId = subjectId;
    _currentSubjectName = subjectName;
    _currentTeacherId = teacherId;
    _currentTimeSlot = timeSlot;
    _roomCode = _generateRoomCode();
    _presentStudentIds.clear(); // reset for new session

    final router = Router()
      ..get('/ping', _handlePing)
      ..post('/validate-otp', _handleValidateOtp)
      ..get('/session-info', _handleSessionInfo);

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router);

    try {
      _serverIp = await NetworkInfo().getWifiIP();
      _server = await io.serve(handler, InternetAddress.anyIPv4, lanPort);
      await _startUdpListener();
      return _serverIp;
    } catch (e) {
      return null;
    }
  }

  Future<void> _startUdpListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, udpPort, reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram == null) return;
          try {
            final data = jsonDecode(utf8.decode(datagram.data))
            as Map<String, dynamic>;
            final requestedCode = data['roomCode'] as String?;
            if (requestedCode == _roomCode && _serverIp != null) {
              final reply = jsonEncode({
                'roomCode': _roomCode,
                'ip': _serverIp,
                'port': lanPort,
                'timeSlot': _currentTimeSlot,
              });
              _udpSocket!.send(
                  utf8.encode(reply), datagram.address, datagram.port);
            }
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> stopServer() async {
    _udpSocket?.close();
    _udpSocket = null;
    await _server?.close(force: true);
    _server = null;
    _currentOtp = null;
    _otpExpiresAt = null;
    _roomCode = null;
  }

  void updateOtp({required String otp, required DateTime expiresAt}) {
    _currentOtp = otp;
    _otpExpiresAt = expiresAt;
  }

  Response _handlePing(Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'online',
        'roomCode': _roomCode ?? '',
        'time': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleSessionInfo(Request request) {
    if (_currentOtp == null) {
      return Response.notFound(
        jsonEncode({'error': 'No active session'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({
        'subjectId': _currentSubjectId,
        'subjectName': _currentSubjectName,
        'teacherId': _currentTeacherId,
        'timeSlot': _currentTimeSlot,
        'roomCode': _roomCode,
        'expiresAt': _otpExpiresAt?.toIso8601String(),
        'active': true,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleValidateOtp(Request request) async {
    try {
      final body =
      jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final otp = body['otp'] as String?;
      final studentId = body['studentId'] as int?;
      final studentName = body['studentName'] as String?; // capture name

      if (otp == null || studentId == null) {
        return _jsonResponse(
            {'success': false, 'error': 'Missing otp or studentId'}, 400);
      }
      if (_currentOtp == null || _otpExpiresAt == null) {
        return _jsonResponse(
            {'success': false, 'error': 'No active OTP session'}, 400);
      }
      if (otp != _currentOtp) {
        return _jsonResponse({'success': false, 'error': 'Invalid OTP'}, 400);
      }
      if (DateTime.now().isAfter(_otpExpiresAt!)) {
        return _jsonResponse(
            {'success': false, 'error': 'OTP has expired'}, 400);
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final alreadyMarked = await DatabaseService.instance.hasAlreadyMarked(
          studentId, _currentSubjectId!, today, _currentTimeSlot!);

      if (alreadyMarked) {
        return _jsonResponse(
            {'success': false, 'error': 'Attendance already marked'}, 409);
      }

      // Save with studentName and subjectName for offline display
      final record = AttendanceRecord(
        studentId: studentId,
        studentName: studentName,          // ← save student name
        subjectId: _currentSubjectId!,
        subjectName: _currentSubjectName,  // ← save subject name
        teacherId: _currentTeacherId!,
        attendanceDate: today,
        timeSlot: _currentTimeSlot!,
        status: 'PRESENT',
        markedAt: DateTime.now().toIso8601String(),
        isSynced: false,
      );
      await DatabaseService.instance.insertAttendance(record);

      // Track this student as PRESENT for the session finalizer
      if (!_presentStudentIds.contains(studentId)) {
        _presentStudentIds.add(studentId);
      }

      return _jsonResponse({
        'success': true,
        'message': 'Attendance marked successfully',
        'studentId': studentId,
        'date': today,
      }, 200);
    } catch (e) {
      return _jsonResponse({'success': false, 'error': e.toString()}, 500);
    }
  }

  Response _jsonResponse(Map<String, dynamic> data, int status) {
    return Response(status,
        body: jsonEncode(data),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        });
  }

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          });
        }
        final response = await handler(request);
        return response
            .change(headers: {'Access-Control-Allow-Origin': '*'});
      };
    };
  }
}