import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/captured_location.dart';
import '../models/crop_config.dart';
import 'supabase_storage_service.dart';

/// One category's captured data for a single entry, immediately before
/// or during upload.
class CategoryUploadData {
  final double? weightGm;
  final String? textValue;
  final File? photoFile;

  const CategoryUploadData({this.weightGm, this.textValue, this.photoFile});

  bool get isEmpty => weightGm == null && textValue == null && photoFile == null;
}

/// Uploads one complete grain-quality entry.
///
/// Photos go to Supabase Storage (Firebase Storage requires a billing
/// account; Supabase's free tier doesn't); metadata goes to Firestore.
/// Idempotent by design: every image is written to a deterministic path
/// (`samples/{cropType}/{entryId}/{category}.jpg`, upserted) and the
/// Firestore document uses `entryId` as its id with a merge write, so
/// retrying an entry that partially succeeded never creates duplicates.
class GrainUploadService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SupabaseStorageService _storage = SupabaseStorageService();

  /// A signed-in worker is a precondition to reaching any screen that
  /// submits data (see LoginScreen/ProfileSetupScreen in main.dart), so
  /// this just reads the current session - no anonymous fallback.
  String ensureSignedIn() {
    final current = _auth.currentUser;
    if (current == null) {
      throw StateError('No worker is signed in.');
    }
    return current.uid;
  }

  Future<void> submitEntry({
    required CropConfig crop,
    required String entryId,
    required Map<String, CategoryUploadData> categories,
    required double? moisture,
    required String? supplier,
    required String? notes,
    required CapturedLocation location,
    required DateTime createdAtDevice,
  }) async {
    debugPrint('[upload] submitEntry start: $entryId');
    final uid = ensureSignedIn();

    final categoriesJson = <String, dynamic>{};
    for (final entry in categories.entries) {
      final key = entry.key;
      final data = entry.value;
      if (data.isEmpty) continue;

      String? storagePath;
      if (data.photoFile != null) {
        debugPrint('[upload] uploading photo for category=$key ...');
        storagePath = await _storage.uploadPhoto(
          file: data.photoFile!,
          cropType: crop.cropType,
          entryId: entryId,
          category: key,
        );
        debugPrint('[upload] photo uploaded for category=$key -> $storagePath');
      }

      categoriesJson[key] = {
        if (data.weightGm != null) 'weightGm': data.weightGm,
        if (data.textValue != null) 'textValue': data.textValue,
        if (storagePath != null) 'storagePath': storagePath,
      };
    }

    final docData = <String, dynamic>{
      'entryId': entryId,
      'cropType': crop.cropType,
      'categories': categoriesJson,
      'moisture': moisture,
      'supplier': (supplier == null || supplier.trim().isEmpty)
          ? null
          : supplier.trim(),
      'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      'location': location.toJson(),
      'createdAtDevice': createdAtDevice.toIso8601String(),
      'uploadedAtServer': FieldValue.serverTimestamp(),
      'authUid': uid,
      'storageProvider': 'supabase',
      'schemaVersion': 3,
    };

    debugPrint('[upload] writing firestore doc $entryId ...');
    await _firestore
        .collection(crop.firestoreCollection)
        .doc(entryId)
        .set(docData, SetOptions(merge: true))
        .timeout(const Duration(seconds: 20));
    debugPrint('[upload] firestore doc written: $entryId');
  }
}
