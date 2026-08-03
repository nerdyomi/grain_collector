class CapturedLocation {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final bool captured;

  const CapturedLocation({
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.captured,
  });

  static const notCaptured = CapturedLocation(captured: false);

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'captured': captured,
  };

  factory CapturedLocation.fromJson(Map<String, dynamic> json) =>
      CapturedLocation(
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        captured: json['captured'] as bool? ?? false,
      );
}
