import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/supabase_config.dart';

/// Uploads photos to Supabase Storage over its REST API. Deterministic
/// object paths (`samples/{cropType}/{entryId}/{category}.jpg`) make retries
/// idempotent: re-uploading the same path just overwrites it (`x-upsert`).
class SupabaseStorageService {
  Future<String> uploadPhoto({
    required File file,
    required String cropType,
    required String entryId,
    required String category,
  }) async {
    final path = 'samples/$cropType/$entryId/$category.jpg';
    final uri = Uri.parse(
      '${SupabaseConfig.projectUrl}/storage/v1/object/${SupabaseConfig.bucket}/$path',
    );

    final bytes = await file.readAsBytes();
    final response = await http
        .post(
          uri,
          headers: {
            'apikey': SupabaseConfig.publishableKey,
            'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
            'Content-Type': 'image/jpeg',
            'x-upsert': 'true',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Supabase upload failed (${response.statusCode}): ${response.body}',
      );
    }

    return path;
  }
}
