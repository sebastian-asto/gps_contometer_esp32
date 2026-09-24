class ContometerDevice {
  const ContometerDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.counter,
    required this.batteryPercent,
    required this.lastSync,
  });

  final String id;
  final String name;
  final int rssi;
  final int counter;
  final int batteryPercent;
  final DateTime lastSync;

  ContometerDevice copyWith({
    String? name,
    int? counter,
    int? rssi,
    int? batteryPercent,
    DateTime? lastSync,
  }) {
    return ContometerDevice(
      id: id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      counter: counter ?? this.counter,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}
