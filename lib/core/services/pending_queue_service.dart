import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/captured_location.dart';

class PendingCategoryData {
  final double? weightGm;
  final String? localPhotoPath;

  const PendingCategoryData({this.weightGm, this.localPhotoPath});

  Map<String, dynamic> toJson() => {
    'weightGm': weightGm,
    'localPhotoPath': localPhotoPath,
  };

  factory PendingCategoryData.fromJson(Map<String, dynamic> json) =>
      PendingCategoryData(
        weightGm: (json['weightGm'] as num?)?.toDouble(),
        localPhotoPath: json['localPhotoPath'] as String?,
      );
}

/// A locally-persisted entry waiting to be uploaded. Created the moment a
/// submission can't reach Firebase immediately (no connectivity, or an
/// upload error) so the worker's data is never lost.
class PendingEntry {
  final String entryId;
  final String cropType;
  final Map<String, PendingCategoryData> categories;
  final String? moisture;
  final String? notes;
  final CapturedLocation location;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  const PendingEntry({
    required this.entryId,
    required this.cropType,
    required this.categories,
    required this.moisture,
    required this.notes,
    required this.location,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
  });

  PendingEntry copyWith({int? retryCount, String? lastError}) => PendingEntry(
    entryId: entryId,
    cropType: cropType,
    categories: categories,
    moisture: moisture,
    notes: notes,
    location: location,
    createdAt: createdAt,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError ?? this.lastError,
  );

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'cropType': cropType,
    'categories': categories.map((k, v) => MapEntry(k, v.toJson())),
    'moisture': moisture,
    'notes': notes,
    'location': location.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastError': lastError,
  };

  factory PendingEntry.fromJson(Map<String, dynamic> json) => PendingEntry(
    entryId: json['entryId'] as String,
    cropType: json['cropType'] as String,
    categories: (json['categories'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, PendingCategoryData.fromJson(v)),
    ),
    moisture: json['moisture'] as String?,
    notes: json['notes'] as String?,
    location: CapturedLocation.fromJson(json['location']),
    createdAt: DateTime.parse(json['createdAt'] as String),
    retryCount: json['retryCount'] as int? ?? 0,
    lastError: json['lastError'] as String?,
  );
}

/// Simple JSON-file-backed queue for entries pending upload. Kept
/// deliberately lightweight for the current MVP iteration; can be
/// replaced by a Drift-backed queue later without changing callers,
/// since callers only interact through this class's methods.
///
/// All reads/writes go through [_serialized] so concurrent callers (e.g. a
/// background retry kicked off right after Submit, racing with a manual
/// retry from the Pending Submissions screen) can never interleave two
/// read-modify-write cycles and corrupt the file.
class PendingQueueService {
  static Future<void> _writeLock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${dir.path}/pending_photos');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return File('${dir.path}/pending_queue.json');
  }

  /// Copies a captured photo into app-controlled permanent storage so it
  /// survives OS cleanup of temporary/cache directories.
  Future<File> persistPhoto(
    File source,
    String entryId,
    String category,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final entryDir = Directory('${dir.path}/pending_photos/$entryId');
    if (!await entryDir.exists()) {
      await entryDir.create(recursive: true);
    }
    final destination = File('${entryDir.path}/$category.jpg');
    return source.copy(destination.path);
  }

  Future<List<PendingEntry>> _readAllUnlocked() async {
    final file = await _queueFile();
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.trim().isEmpty) return [];
    try {
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => PendingEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException catch (e) {
      // A corrupted file must never brick the queue permanently - back it
      // up for inspection and start fresh rather than throwing forever.
      debugPrint('Pending queue file corrupted, resetting: $e');
      final backup = File('${file.path}.corrupted-${DateTime.now().millisecondsSinceEpoch}');
      await file.copy(backup.path);
      await file.writeAsString('[]');
      return [];
    }
  }

  Future<List<PendingEntry>> loadAll() => _serialized(_readAllUnlocked);

  Future<void> _saveAllUnlocked(List<PendingEntry> entries) async {
    final file = await _queueFile();
    final tempFile = File('${file.path}.tmp');
    // Write to a temp file then rename over the real one: rename is atomic
    // on the same filesystem, so a crash/kill mid-write can never leave
    // pending_queue.json half-written.
    await tempFile.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    await tempFile.rename(file.path);
  }

  Future<void> add(PendingEntry entry) => _serialized(() async {
    final entries = await _readAllUnlocked();
    entries.removeWhere((e) => e.entryId == entry.entryId);
    entries.add(entry);
    await _saveAllUnlocked(entries);
  });

  Future<void> remove(String entryId) => _serialized(() async {
    final entries = await _readAllUnlocked();
    entries.removeWhere((e) => e.entryId == entryId);
    await _saveAllUnlocked(entries);
    final dir = await getApplicationDocumentsDirectory();
    final entryDir = Directory('${dir.path}/pending_photos/$entryId');
    if (await entryDir.exists()) {
      await entryDir.delete(recursive: true);
    }
  });

  Future<void> markError(String entryId, String error) => _serialized(() async {
    final entries = await _readAllUnlocked();
    final index = entries.indexWhere((e) => e.entryId == entryId);
    if (index == -1) return;
    entries[index] = entries[index].copyWith(
      retryCount: entries[index].retryCount + 1,
      lastError: error,
    );
    await _saveAllUnlocked(entries);
  });
}
