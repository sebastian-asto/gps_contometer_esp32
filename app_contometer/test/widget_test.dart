import 'package:app_contometer/models/contometer_device.dart';
import 'package:app_contometer/screens/device_scan_screen.dart';
import 'package:app_contometer/services/ble_contometer_service.dart';
import 'package:app_contometer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBleClient implements ContometerBleClient {
  @override
  BleStatus get status => BleStatus.ready;

  @override
  Stream<BleStatus> get statusStream => const Stream.empty();

  @override
  Stream<ContometerDevice> scan() => const Stream.empty();

  @override
  Future<BleContometerSession> connect(ContometerDevice device) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('shows the BLE discovery screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DeviceScanScreen(bleClient: _FakeBleClient()),
      ),
    );

    expect(find.text('Equipos cercanos'), findsOneWidget);
    expect(find.text('Buscar contómetros'), findsOneWidget);
    expect(find.text('Aún no encontramos equipos'), findsOneWidget);
  });
}
