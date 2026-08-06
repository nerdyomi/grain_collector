import 'dart:io';

import '../models/crop_config.dart';
import 'grain_upload_service.dart';
import 'pending_queue_service.dart';

/// Attempts to upload every queued entry. Entries that fail again stay in
/// the queue with an updated retry count / last error so the Submissions
/// screen can surface them.
class SyncService {
  final PendingQueueService queue;
  final GrainUploadService uploader;

  SyncService({required this.queue, required this.uploader});

  Future<void> retryAll() async {
    final entries = await queue.loadAll();
    for (final entry in entries) {
      await retryOne(entry.entryId);
    }
  }

  Future<bool> retryOne(String entryId) async {
    final entries = await queue.loadAll();
    final entry = entries.where((e) => e.entryId == entryId).firstOrNull;
    if (entry == null) return false;

    try {
      final crop = CropCatalog.byType(entry.cropType);
      final categories = <String, CategoryUploadData>{};
      for (final e in entry.categories.entries) {
        categories[e.key] = CategoryUploadData(
          weightGm: e.value.weightGm,
          textValue: e.value.textValue,
          photoFile: e.value.localPhotoPath != null
              ? File(e.value.localPhotoPath!)
              : null,
        );
      }

      await uploader.submitEntry(
        crop: crop,
        entryId: entry.entryId,
        categories: categories,
        moisture: entry.moisture,
        supplier: entry.supplier,
        notes: entry.notes,
        location: entry.location,
        createdAtDevice: entry.createdAt,
      );
      await queue.remove(entryId);
      return true;
    } catch (err) {
      await queue.markError(entryId, err.toString());
      return false;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
