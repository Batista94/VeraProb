class SpoofingDetectedException implements Exception {
  final String deviceId;
  final String reason;

  SpoofingDetectedException({required this.deviceId, required this.reason});

  @override
  String toString() => 'SpoofingDetectedException: $reason (device: $deviceId)';
}
