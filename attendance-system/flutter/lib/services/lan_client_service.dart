import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class LanClientService {
  LanClientService._internal();
  static final LanClientService instance = LanClientService._internal();

  static const int lanPort = 8181;
  static const int udpPort = 8182;
  String? _teacherIp;

  String? get teacherIp => _teacherIp;

  void setTeacherIp(String ip) => _teacherIp = ip;

  Dio get _dio => Dio(BaseOptions(
    baseUrl: 'http://$_teacherIp:$lanPort',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  // ── Ping with short timeout ───────────────────────────────────
  Future<bool> pingTeacher(String ip) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: 'http://$ip:$lanPort',
        connectTimeout: const Duration(milliseconds: 800),
        receiveTimeout: const Duration(milliseconds: 800),
      ));
      final response = await dio.get('/ping');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── FAST: UDP broadcast discovery — finds teacher in < 500ms ─
  Future<String?> findByRoomCodeUDP(String myIp, String roomCode) async {
    RawDatagramSocket? socket;
    try {
      // Bind to any port
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Build broadcast message
      final message = jsonEncode({'roomCode': roomCode, 'from': myIp});
      final data = utf8.encode(message);

      // Calculate broadcast address from myIp
      final parts = myIp.split('.');
      final broadcastIp = parts.length == 4
          ? '${parts[0]}.${parts[1]}.${parts[2]}.255'
          : '255.255.255.255';

      // Send broadcast — reaches ALL devices on LAN instantly
      socket.send(data, InternetAddress(broadcastIp), udpPort);

      // Also try global broadcast
      socket.send(data, InternetAddress('255.255.255.255'), udpPort);

      // Wait for response with 2 second timeout
      final completer = Completer<String?>();
      Timer? timeout;

      timeout = Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram == null) return;
          try {
            final response =
            jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
            final receivedCode = response['roomCode'] as String?;
            final teacherIp = response['ip'] as String?;

            if (receivedCode == roomCode && teacherIp != null) {
              timeout?.cancel();
              if (!completer.isCompleted) completer.complete(teacherIp);
            }
          } catch (_) {}
        }
      });

      final result = await completer.future;
      if (result != null) {
        _teacherIp = result;
        return result;
      }
    } catch (e) {
      print('UDP discovery failed: $e');
    } finally {
      socket?.close();
    }
    return null;
  }

  // ── Find teacher by room code (UDP first, then HTTP fallback) ─
  Future<String?> findByRoomCode(String myIp, String roomCode) async {
    // Try UDP broadcast first — instant
    final udpResult = await findByRoomCodeUDP(myIp, roomCode);
    if (udpResult != null) return udpResult;

    // Fallback: HTTP scan (if UDP blocked by firewall)
    return _findByRoomCodeHttp(myIp, roomCode);
  }

  // HTTP fallback scan
  Future<String?> _findByRoomCodeHttp(String myIp, String roomCode) async {
    final parts = myIp.split('.');
    if (parts.length != 4) return null;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final myLastOctet = int.tryParse(parts[3]) ?? 0;

    // Priority IPs
    final priorityIps = [
      '$subnet.1', '$subnet.2',
      '$subnet.100', '$subnet.101', '$subnet.102',
      '$subnet.103', '$subnet.104', '$subnet.105',
      '192.168.43.1', '192.168.1.1', '192.168.0.1',
    ].where((ip) => ip != myIp).toList();

    for (final ip in priorityIps) {
      final code = await _getRoomCode(ip);
      if (code == roomCode) {
        _teacherIp = ip;
        return ip;
      }
    }

    // Batch scan remaining IPs
    final allHosts = List.generate(254, (i) => i + 1)
        .where((h) => h != myLastOctet)
        .where((h) => !priorityIps.contains('$subnet.$h'))
        .toList();

    const batchSize = 50; // increased batch size
    for (int i = 0; i < allHosts.length; i += batchSize) {
      final batch = allHosts.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((host) async {
          final ip = '$subnet.$host';
          final code = await _getRoomCode(ip);
          if (code == roomCode) return ip;
          return null;
        }),
      );
      final found =
      results.firstWhere((ip) => ip != null, orElse: () => null);
      if (found != null) {
        _teacherIp = found;
        return found;
      }
    }
    return null;
  }

  Future<String?> _getRoomCode(String ip) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: 'http://$ip:$lanPort',
        connectTimeout: const Duration(milliseconds: 600),
        receiveTimeout: const Duration(milliseconds: 600),
      ));
      final response = await dio.get('/ping');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['roomCode'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ── Auto-discover any teacher (fallback) ─────────────────────
  Future<String?> discoverTeacher(String myIp) async {
    final parts = myIp.split('.');
    if (parts.length != 4) return null;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final myLastOctet = int.tryParse(parts[3]) ?? 0;

    final priorityIps = [
      '$subnet.1', '$subnet.2',
      '$subnet.100', '$subnet.101', '$subnet.102',
      '$subnet.103', '$subnet.104', '$subnet.105',
      '192.168.43.1', '192.168.1.1', '192.168.0.1',
    ].where((ip) => ip != myIp).toList();

    for (final ip in priorityIps) {
      if (await pingTeacher(ip)) {
        _teacherIp = ip;
        return ip;
      }
    }

    final allHosts = List.generate(254, (i) => i + 1)
        .where((h) => h != myLastOctet)
        .where((h) => !priorityIps.contains('$subnet.$h'))
        .toList();

    const batchSize = 50;
    for (int i = 0; i < allHosts.length; i += batchSize) {
      final batch = allHosts.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((host) async {
          final ip = '$subnet.$host';
          if (await pingTeacher(ip)) return ip;
          return null;
        }),
      );
      final found =
      results.firstWhere((ip) => ip != null, orElse: () => null);
      if (found != null) {
        _teacherIp = found;
        return found;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getSessionInfo() async {
    try {
      final response = await _dio.get('/session-info');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> submitOtp({
    required String otp,
    required int studentId,
    required String studentName,
  }) async {
    try {
      final response = await _dio.post('/validate-otp', data: {
        'otp': otp,
        'studentId': studentId,
        'studentName': studentName,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'error': 'Connection failed: ${e.message}'};
    }
  }
}