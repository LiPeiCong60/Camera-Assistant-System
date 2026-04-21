import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/capture_record.dart';
import '../models/capture_session_summary.dart';
import '../models/template_summary.dart';

class MobileCacheService {
  static const String _templatesKey = 'mobile.cache.templates';
  static const String _historySessionsKey = 'mobile.cache.history_sessions';
  static const String _historyCapturesKey = 'mobile.cache.history_captures';

  Future<List<TemplateSummary>> readTemplates() async {
    final items = await _readList(_templatesKey);
    return items.map(TemplateSummary.fromJson).toList(growable: false);
  }

  Future<void> writeTemplates(List<TemplateSummary> items) async {
    await _writeList(
      _templatesKey,
      items.map((item) => item.toJson()).toList(growable: false),
    );
  }

  Future<void> upsertTemplate(TemplateSummary item) async {
    final items = await readTemplates();
    final next = <TemplateSummary>[item];
    next.addAll(items.where((existing) => existing.id != item.id));
    await writeTemplates(next);
  }

  Future<void> removeTemplate(int templateId) async {
    final items = await readTemplates();
    final next = items.where((existing) => existing.id != templateId).toList(
      growable: false,
    );
    await writeTemplates(next);
  }

  Future<List<CaptureSessionSummary>> readHistorySessions() async {
    final items = await _readList(_historySessionsKey);
    return items.map(CaptureSessionSummary.fromJson).toList(growable: false);
  }

  Future<void> writeHistorySessions(List<CaptureSessionSummary> items) async {
    await _writeList(
      _historySessionsKey,
      items.map((item) => item.toJson()).toList(growable: false),
    );
  }

  Future<void> prependHistorySession(CaptureSessionSummary item) async {
    final items = await readHistorySessions();
    final next = <CaptureSessionSummary>[item];
    next.addAll(items.where((existing) => existing.id != item.id));
    await writeHistorySessions(next);
  }

  Future<List<CaptureRecord>> readHistoryCaptures() async {
    final items = await _readList(_historyCapturesKey);
    return items.map(CaptureRecord.fromJson).toList(growable: false);
  }

  Future<void> writeHistoryCaptures(List<CaptureRecord> items) async {
    await _writeList(
      _historyCapturesKey,
      items.map((item) => item.toJson()).toList(growable: false),
    );
  }

  Future<void> prependHistoryCapture(CaptureRecord item) async {
    final items = await readHistoryCaptures();
    final next = <CaptureRecord>[item];
    next.addAll(items.where((existing) => existing.id != item.id));
    await writeHistoryCaptures(next);
  }

  Future<void> clearContentCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_templatesKey);
    await prefs.remove(_historySessionsKey);
    await prefs.remove(_historyCapturesKey);
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items));
  }
}
