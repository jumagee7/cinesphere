import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
  success,
}

class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final LogLevel level;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.level = LogLevel.info,
    this.details,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  Map<String, dynamic> toJson() => {
        't': timestamp.millisecondsSinceEpoch,
        'tag': tag,
        'm': message,
        'l': level.index,
        if (details != null) 'd': details,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['t'] as int? ?? 0),
        tag: json['tag'] as String? ?? 'General',
        message: json['m'] as String? ?? '',
        level: LogLevel.values[
            (json['l'] as int? ?? 1).clamp(0, LogLevel.values.length - 1)],
        details: json['d'] as String?,
      );
}

/// Central in-app diagnostic log hub.
///
/// Records every step of stream resolution, WebView events, video player
/// playback, and network operations into memory and local storage so users
/// on devices that cannot be connected to a debugger (e.g. non-rooted TV boxes,
/// standalone phones) can view, filter, and export logs with one tap.
class DiagnosticService extends ChangeNotifier {
  static final DiagnosticService instance = DiagnosticService._internal();
  factory DiagnosticService() => instance;
  DiagnosticService._internal();

  static const String _prefsKey = 'cinesphere_diagnostic_logs_v1';
  static const int _maxInMemory = 600;
  static const int _maxPersisted = 150;

  final List<LogEntry> _logs = [];
  Timer? _saveDebounceTimer;
  bool _initialized = false;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  int get errorCount =>
      _logs.where((l) => l.level == LogLevel.error).length;

  int get warningCount =>
      _logs.where((l) => l.level == LogLevel.warning).length;

  int get successCount =>
      _logs.where((l) => l.level == LogLevel.success).length;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = jsonDecode(raw) as List;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _logs.add(LogEntry.fromJson(item));
          }
        }
      }
    } catch (e) {
      debugPrint('[DiagnosticService] Error loading stored logs: $e');
    }

    log(
      'System',
      'DiagnosticService initialized. Platform: ${_platformSummary()}',
      level: LogLevel.info,
    );
  }

  void log(
    String tag,
    String message, {
    LogLevel level = LogLevel.info,
    String? details,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
      details: details,
    );

    _logs.add(entry);
    if (_logs.length > _maxInMemory) {
      _logs.removeAt(0);
    }

    // Echo to dev.log & debugPrint for console if attached
    dev.log(message, name: tag);
    debugPrint('[$tag] $message');
    if (details != null && details.isNotEmpty) {
      debugPrint('[$tag][Details] $details');
    }

    notifyListeners();
    _schedulePersist();
  }

  void info(String tag, String message, [String? details]) =>
      log(tag, message, level: LogLevel.info, details: details);

  void warn(String tag, String message, [String? details]) =>
      log(tag, message, level: LogLevel.warning, details: details);

  void warning(String tag, String message, [String? details]) =>
      warn(tag, message, details);

  void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final d = StringBuffer();
    if (error != null) d.writeln('Error: $error');
    if (stackTrace != null) d.writeln('Stack:\n$stackTrace');
    log(
      tag,
      message,
      level: LogLevel.error,
      details: d.isEmpty ? null : d.toString(),
    );
  }

  void success(String tag, String message, [String? details]) =>
      log(tag, message, level: LogLevel.success, details: details);

  void clear() {
    _logs.clear();
    notifyListeners();
    _saveToPrefs();
  }

  void _schedulePersist() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 1500), _saveToPrefs);
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _logs.length > _maxPersisted
          ? _logs.sublist(_logs.length - _maxPersisted)
          : _logs;
      final encoded = jsonEncode(toSave.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
  }

  String _platformSummary() {
    if (kIsWeb) return 'Web Browser';
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'Unknown';
    }
  }

  String buildReport() {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════════════════');
    buf.writeln('CINESPHERE DIAGNOSTIC REPORT');
    buf.writeln('Time: ${DateTime.now().toIso8601String()}');
    buf.writeln('Platform: ${_platformSummary()}');
    buf.writeln('Total Logs: ${_logs.length} (Errors: $errorCount, Warnings: $warningCount)');
    buf.writeln('═══════════════════════════════════════════════════════\n');

    for (final e in _logs) {
      final lvl = e.level.name.toUpperCase().padRight(7);
      final tag = '[${e.tag}]'.padRight(18);
      buf.writeln('${e.formattedTime} $lvl $tag ${e.message}');
      if (e.details != null && e.details!.isNotEmpty) {
        for (final line in e.details!.split('\n')) {
          if (line.trim().isNotEmpty) {
            buf.writeln('    | $line');
          }
        }
      }
    }
    buf.writeln('\n═══════════════════════════════════════════════════════');
    return buf.toString();
  }

  Future<void> copyReportToClipboard(BuildContext context) async {
    final report = buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Diagnostic report (${_logs.length} events) copied to clipboard!',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E24),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
