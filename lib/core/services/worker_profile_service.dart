import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

class WorkerProfile {
  final String workerId;
  final String name;
  final String designation;

  const WorkerProfile({
    required this.workerId,
    required this.name,
    required this.designation,
  });

  Map<String, dynamic> toJson() => {
    'workerId': workerId,
    'name': name,
    'designation': designation,
  };

  factory WorkerProfile.fromJson(Map<String, dynamic> json) => WorkerProfile(
    workerId: json['workerId'] as String,
    name: json['name'] as String,
    designation: json['designation'] as String,
  );
}

/// A worker's Name + Designation(পদবি), captured once on first login.
/// Cached locally (fast, offline-safe on every login after the first) and
/// backed by Firestore `workers/{uid}` so it survives a reinstall.
class WorkerProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/worker_profile.json');
  }

  Future<WorkerProfile?> loadCached(String workerId) async {
    final file = await _cacheFile();
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final profile = WorkerProfile.fromJson(json);
      return profile.workerId == workerId ? profile : null;
    } catch (_) {
      return null;
    }
  }

  Future<WorkerProfile?> fetchFromFirestore(String workerId) async {
    final doc = await _firestore
        .collection('workers')
        .doc(workerId)
        .get()
        .timeout(const Duration(seconds: 20));
    if (!doc.exists) return null;
    final data = doc.data()!;
    return WorkerProfile(
      workerId: workerId,
      name: data['name'] as String? ?? '',
      designation: data['designation'] as String? ?? '',
    );
  }

  Future<void> save(WorkerProfile profile) async {
    await _firestore
        .collection('workers')
        .doc(profile.workerId)
        .set({
          'name': profile.name,
          'designation': profile.designation,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
    await cacheLocally(profile);
  }

  /// Writes the local cache only, without touching Firestore - used right
  /// after a Firestore *read* so we don't immediately write the same data
  /// straight back.
  Future<void> cacheLocally(WorkerProfile profile) async {
    final file = await _cacheFile();
    await file.writeAsString(jsonEncode(profile.toJson()));
  }

  Future<void> clearCache() async {
    final file = await _cacheFile();
    if (await file.exists()) await file.delete();
  }
}
