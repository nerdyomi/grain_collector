import 'package:geolocator/geolocator.dart';

import '../models/captured_location.dart';

/// One-shot GPS capture. Never tracks continuously and never blocks
/// the caller indefinitely - always returns within [timeout] or fails soft.
class LocationService {
  Future<CapturedLocation> captureCurrentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return CapturedLocation.notCaptured;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return CapturedLocation.notCaptured;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );

      return CapturedLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        captured: true,
      );
    } catch (_) {
      return CapturedLocation.notCaptured;
    }
  }
}
