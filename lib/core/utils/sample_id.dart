import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a globally-unique, offline-safe entry id such as
/// `MZ-20260803-3f9c2b1a...`. Stable across retries: generate once per
/// entry and reuse for local storage, Storage paths, and the Firestore
/// document id.
String generateEntryId(String prefix) {
  final date = DateFormat('yyyyMMdd').format(DateTime.now());
  return '$prefix-$date-${_uuid.v4()}';
}
