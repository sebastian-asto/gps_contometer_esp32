import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../models/contometer_device.dart';

abstract final class BleProtocol {
  static final service = Uuid.parse('7b1e4000-7a2b-4c9d-ae55-3f49c2a10001');
  static final status = Uuid.parse('7b1e4000-7a2b-4c9d-ae55-3f49c2a10002');
  static final command = Uuid.parse('7b1e4000-7a2b-4c9d-ae55-3f49c2a10003');
  static final name = Uuid.parse('7b1e4000-7a2b-4c9d-ae55-3f49c2a10004');

  static const resetCounter = 0x01;
  static const testDisplay = 0x02;
}

class ContometerStatus {
  const ContometerStatus({
    required this.counter,
    required this.speedKmh,
    required this.speedLimitKmh,
    required this.gpsValid,
    required this.satellites,
    required this.speedState,
  });

  const ContometerStatus.empty()
    : counter = 0,
      speedKmh = 0,
      speedLimitKmh = 30,
      gpsValid = false,
      satellites = 0,
      speedState = 0;

  final int counter;
  final double speedKmh;
  final double speedLimitKmh;
  final bool gpsValid;
  final int satellites;
  final int speedState;

  factory ContometerStatus.fromBytes(List<int> bytes) {
    if (bytes.length < 10 || bytes[0] != 1) {
      throw const FormatException('Estado BLE incompatible');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return ContometerStatus(
      counter: data.getUint16(1, Endian.little),
      speedKmh: data.getUint16(3, Endian.little) / 10,
      speedLimitKmh: data.getUint16(5, Endian.little) / 10,
      gpsValid: (bytes[7] & 0x01) != 0,
      satellites: bytes[8],
      speedState: bytes[9],
    );
  }
}

abstract interface class ContometerBleClient {
  BleStatus get status;
  Stream<BleStatus> get statusStream;
  Stream<ContometerDevice> scan();
  Future<BleContometerSession> connect(ContometerDevice device);
}

class BleContometerClient implements ContometerBleClient {
  BleContometerClient({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  @override
  BleStatus get status => _ble.status;
  @override
  Stream<BleStatus> get statusStream => _ble.statusStream;

  @override
  Stream<ContometerDevice> scan() {
    return _ble
        .scanForDevices(
          withServices: [BleProtocol.service],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .map(
          (device) => ContometerDevice(
            id: device.id,
            name: device.name.isEmpty ? 'Contómetro ${device.id}' : device.name,
            rssi: device.rssi,
            counter: 0,
            batteryPercent: 0,
            lastSync: DateTime.now(),
          ),
        );
  }

  @override
  Future<BleContometerSession> connect(ContometerDevice device) async {
    final session = BleContometerSession._(_ble, device);
    await session.open();
    return session;
  }
}

class BleContometerSession {
  BleContometerSession._(this._ble, this.device)
    : _statusCharacteristic = QualifiedCharacteristic(
        serviceId: BleProtocol.service,
        characteristicId: BleProtocol.status,
        deviceId: device.id,
      ),
      _commandCharacteristic = QualifiedCharacteristic(
        serviceId: BleProtocol.service,
        characteristicId: BleProtocol.command,
        deviceId: device.id,
      ),
      _nameCharacteristic = QualifiedCharacteristic(
        serviceId: BleProtocol.service,
        characteristicId: BleProtocol.name,
        deviceId: device.id,
      );

  final FlutterReactiveBle _ble;
  ContometerDevice device;
  final QualifiedCharacteristic _statusCharacteristic;
  final QualifiedCharacteristic _commandCharacteristic;
  final QualifiedCharacteristic _nameCharacteristic;
  final _statusController = StreamController<ContometerStatus>.broadcast();
  final _connectionController =
      StreamController<DeviceConnectionState>.broadcast();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  ContometerStatus latestStatus = const ContometerStatus.empty();

  Stream<ContometerStatus> get statusStream => _statusController.stream;
  Stream<DeviceConnectionState> get connectionStream =>
      _connectionController.stream;

  Future<void> open() async {
    final connected = Completer<void>();
    _connectionSubscription = _ble
        .connectToAdvertisingDevice(
          id: device.id,
          withServices: [BleProtocol.service],
          prescanDuration: const Duration(seconds: 3),
          servicesWithCharacteristicsToDiscover: {
            BleProtocol.service: [
              BleProtocol.status,
              BleProtocol.command,
              BleProtocol.name,
            ],
          },
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) {
            _connectionController.add(update.connectionState);
            if (update.connectionState == DeviceConnectionState.connected &&
                !connected.isCompleted) {
              connected.complete();
            } else if (update.connectionState ==
                    DeviceConnectionState.disconnected &&
                !connected.isCompleted) {
              connected.completeError(
                StateError(update.failure?.message ?? 'No se pudo conectar'),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!connected.isCompleted) {
              connected.completeError(error, stackTrace);
            }
          },
        );

    await connected.future.timeout(const Duration(seconds: 16));
    _statusSubscription = _ble
        .subscribeToCharacteristic(_statusCharacteristic)
        .listen(_handleStatus, onError: _statusController.addError);

    final initial = await _ble.readCharacteristic(_statusCharacteristic);
    _handleStatus(initial);

    final nameBytes = await _ble.readCharacteristic(_nameCharacteristic);
    final name = utf8.decode(nameBytes, allowMalformed: true).trim();
    if (name.isNotEmpty) {
      device = device.copyWith(name: name, lastSync: DateTime.now());
    }
  }

  void _handleStatus(List<int> bytes) {
    try {
      latestStatus = ContometerStatus.fromBytes(bytes);
      device = device.copyWith(
        counter: latestStatus.counter,
        lastSync: DateTime.now(),
      );
      _statusController.add(latestStatus);
    } on FormatException catch (error, stackTrace) {
      _statusController.addError(error, stackTrace);
    }
  }

  Future<void> resetCounter() {
    return _ble.writeCharacteristicWithResponse(
      _commandCharacteristic,
      value: const [BleProtocol.resetCounter],
    );
  }

  Future<void> testDisplay(int value) {
    if (value < 0 || value > 999) {
      throw const FormatException('El valor debe estar entre 0 y 999');
    }
    return _ble.writeCharacteristicWithResponse(
      _commandCharacteristic,
      value: [BleProtocol.testDisplay, value & 0xFF, value >> 8],
    );
  }

  Future<void> rename(String name) async {
    final bytes = utf8.encode(name.trim());
    if (bytes.isEmpty || bytes.length > 24) {
      throw const FormatException('El nombre debe ocupar entre 1 y 24 bytes');
    }
    await _ble.writeCharacteristicWithResponse(
      _nameCharacteristic,
      value: bytes,
    );
    device = device.copyWith(name: name.trim(), lastSync: DateTime.now());
  }

  Future<void> close() async {
    await _statusSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _statusController.close();
    await _connectionController.close();
  }
}
