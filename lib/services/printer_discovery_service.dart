import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/app_log.dart';
import '../models/printer_model.dart';

class PrinterScanProgress {
  final int scanned;
  final int total;
  final int found;
  PrinterScanProgress({required this.scanned, required this.total, required this.found});
}

typedef OnScanProgress = void Function(PrinterScanProgress progress);

class PrinterDiscoveryService {
  static int _windowsPrintSeq = 0;

  static Future<List<DiscoveredPrinter>> discoverPrinters({
    OnScanProgress? onProgress,
  }) async {
    if (kIsWeb) return [];
    if (Platform.isWindows) {
      final windowsPrinters = await _discoverWindowsPrinters();
      final networkPrinters = await _discoverNetworkPrinters(onProgress: onProgress);
      final combined = [...windowsPrinters, ...networkPrinters];
      final seen = <String>{};
      final unique = <DiscoveredPrinter>[];
      for (final p in combined) {
        if (seen.add(p.name)) unique.add(p);
      }
      return unique;
    }
    return _discoverNetworkPrinters(onProgress: onProgress);
  }

  static Future<List<DiscoveredPrinter>> _discoverWindowsPrinters() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-Printer | Select-Object Name, PortName, DriverName | ConvertTo-Json',
        ],
      );
      if (result.exitCode != 0) return [];
      final jsonStr = result.stdout as String;
      if (jsonStr.trim().startsWith('[')) {
        final list = _parseJsonList(jsonStr);
        return list.map((item) {
          final name = item['Name'] as String? ?? '';
          final port = item['PortName'] as String? ?? '';
          return DiscoveredPrinter(name: name, portName: port);
        }).where((p) => p.name.isNotEmpty).toList();
      }
      if (jsonStr.trim().startsWith('{')) {
        final item = _parseJsonObject(jsonStr);
        final name = item['Name'] as String? ?? '';
        final port = item['PortName'] as String? ?? '';
        if (name.isNotEmpty) {
          return [DiscoveredPrinter(name: name, portName: port)];
        }
      }
      return [];
    } catch (e) {
      appLog('[PrinterDiscovery] Windows scan error: $e');
      return [];
    }
  }

  static List<Map<String, dynamic>> _parseJsonList(String raw) {
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // The real decoder failed (a PowerShell warning line ahead of the JSON,
      // say). Fall back to the tolerant line scanner.
      return _fallbackParse(raw);
    }
  }

  static Map<String, dynamic> _parseJsonObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Fall through to the tolerant scanner below.
    }
    final list = _fallbackParse(raw);
    return list.isEmpty ? {} : list.first;
  }

  static List<Map<String, dynamic>> _fallbackParse(String raw) {
    final result = <Map<String, dynamic>>[];
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    Map<String, dynamic>? current;
    for (final line in lines) {
      if (line.contains('{')) {
        current = {};
      } else if (line.contains('}')) {
        if (current != null && current.isNotEmpty) {
          result.add(current);
        }
        current = null;
      } else if (current != null && line.contains(':')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          current[parts[0].trim().replaceAll('"', '')] =
              parts.sublist(1).join(':').trim().replaceAll('"', '').replaceAll(',', '');
        }
      }
    }
    return result;
  }

  static Future<List<DiscoveredPrinter>> _discoverNetworkPrinters({
    OnScanProgress? onProgress,
  }) async {
    final printers = <DiscoveredPrinter>[];
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final subnet = _getSubnet(addr.address);
            if (subnet != null) {
              final found = await _scanSubnet(
                subnet,
                addr.address,
                onProgress: onProgress,
              );
              printers.addAll(found);
            }
          }
        }
      }
    } catch (e) {
      appLog('[PrinterDiscovery] Network scan error: $e');
    }
    return printers;
  }

  static String? _getSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  static Future<List<DiscoveredPrinter>> _scanSubnet(
    String subnet,
    String localIp, {
    OnScanProgress? onProgress,
  }) async {
    final printers = <DiscoveredPrinter>[];
    final localLast = int.tryParse(localIp.split('.').last) ?? 0;
    final ips = <String>[];
    for (int i = 1; i <= 254; i++) {
      if (i == localLast) continue;
      ips.add('$subnet$i');
    }

    int scanned = 0;
    const batchSize = 20;
    for (int start = 0; start < ips.length; start += batchSize) {
      final end = min(start + batchSize, ips.length);
      final batch = ips.sublist(start, end);
      final futures = batch.map((ip) => _tryConnect(ip, 9100));
      final results = await Future.wait(futures, eagerError: false);
      for (final result in results) {
        if (result != null) printers.add(result);
      }
      scanned += batch.length;
      onProgress?.call(PrinterScanProgress(
        scanned: scanned,
        total: ips.length,
        found: printers.length,
      ));
    }
    return printers;
  }

  static Future<DiscoveredPrinter?> _tryConnect(String ip, int port) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 150),
      );
      socket.destroy();
      return DiscoveredPrinter(name: 'ESC/POS $ip', portName: ip);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> printRaw(String printerName, List<int> data, {String portName = ''}) async {
    if (kIsWeb) return false;
    final port = portName.trim();
    if (port.isNotEmpty && RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(port)) {
      return _printNetwork(port, data);
    }
    if (Platform.isWindows) return _printWindows(printerName, data);
    return _printNetwork(printerName, data);
  }

  static Future<bool> _printWindows(String printerName, List<int> data) async {
    var tempFile = '';
    try {
      final unique = '${DateTime.now().microsecondsSinceEpoch}_${_windowsPrintSeq++}';
      tempFile = '${Directory.systemTemp.path}\\print_$unique.bin';
      await File(tempFile).writeAsBytes(data);
      // Single-quote both the temp path and the printer name for PowerShell so
      // either may contain spaces/quotes without turning into command injection.
      final escapedPath = tempFile.replaceAll("'", "''");
      final escapedName = printerName.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Get-Content -Encoding Byte '$escapedPath' | Out-Printer -Name '$escapedName'",
        ],
      );
      return result.exitCode == 0;
    } catch (e) {
      appLog('[PrinterDiscovery] Windows print error: $e');
      return false;
    } finally {
      if (tempFile.isNotEmpty) {
        try {
          await File(tempFile).delete();
        } catch (_) {}
      }
    }
  }

  static Future<bool> _printNetwork(String printerName, List<int> data) async {
    try {
      final ip = printerName.replaceAll('ESC/POS ', '').trim();
      final socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(seconds: 5),
      );
      socket.add(data);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      appLog('[PrinterDiscovery] Network print error: $e');
      return false;
    }
  }
}
