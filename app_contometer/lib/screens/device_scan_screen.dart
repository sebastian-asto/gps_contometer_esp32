import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/contometer_device.dart';
import '../services/ble_contometer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/status_pill.dart';
import 'device_workspace_screen.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key, this.bleClient});

  final ContometerBleClient? bleClient;

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  late final ContometerBleClient _bleClient;
  bool _isScanning = false;
  final Map<String, ContometerDevice> _foundDevices = {};
  StreamSubscription<ContometerDevice>? _scanSubscription;
  Timer? _scanTimer;

  List<ContometerDevice> get _devices {
    final devices = _foundDevices.values.toList();
    devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    return devices;
  }

  @override
  void initState() {
    super.initState();
    _bleClient = widget.bleClient ?? BleContometerClient();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_isScanning) return;
    if (!await _ensurePermissions()) return;
    if (_bleClient.status != BleStatus.ready) {
      _showMessage(_bleStatusMessage(_bleClient.status));
      return;
    }

    await _scanSubscription?.cancel();
    _scanTimer?.cancel();
    setState(() {
      _foundDevices.clear();
      _isScanning = true;
    });

    _scanSubscription = _bleClient.scan().listen(
      (device) {
        if (!mounted) return;
        setState(() => _foundDevices[device.id] = device);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _isScanning = false);
        _showMessage('No se pudo buscar por Bluetooth: $error');
      },
    );
    _scanTimer = Timer(const Duration(seconds: 8), _stopScan);
  }

  Future<bool> _ensurePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final result = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scan = result[Permission.bluetoothScan];
    final connect = result[Permission.bluetoothConnect];
    final location = result[Permission.locationWhenInUse];

    if (scan?.isPermanentlyDenied == true ||
        connect?.isPermanentlyDenied == true) {
      _showMessage(
        'Bluetooth está bloqueado. Habilítalo desde los ajustes de la aplicación.',
      );
      await openAppSettings();
      return false;
    }

    // Android 12+ usa scan/connect; Android 11 e inferiores usan ubicación.
    final modernGranted = scan?.isGranted == true && connect?.isGranted == true;
    final legacyGranted = location?.isGranted == true;
    if (!modernGranted && !legacyGranted) {
      _showMessage('Se necesita permiso de Bluetooth para buscar contómetros.');
      return false;
    }
    return true;
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _openDevice(ContometerDevice device) async {
    await _stopScan();
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ConnectingDialog(),
    );

    BleContometerSession session;
    try {
      session = await _bleClient.connect(device);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showMessage('No se pudo conectar: $error');
      return;
    }

    if (!mounted) {
      await session.close();
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
    final updated = await Navigator.of(context).push<ContometerDevice>(
      MaterialPageRoute(
        builder: (_) => DeviceWorkspaceScreen(session: session),
      ),
    );
    await session.close();
    if (updated == null || !mounted) return;
    setState(() => _foundDevices[updated.id] = updated);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _bleStatusMessage(BleStatus status) {
    return switch (status) {
      BleStatus.poweredOff => 'Activa Bluetooth para buscar contómetros.',
      BleStatus.unauthorized => 'Autoriza el uso de Bluetooth en los ajustes.',
      BleStatus.locationServicesDisabled =>
        'Activa los servicios de ubicación para buscar por BLE.',
      BleStatus.unsupported => 'Este teléfono no admite Bluetooth Low Energy.',
      _ => 'Bluetooth todavía no está disponible. Intenta nuevamente.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [_BrandMark(), SizedBox(width: 12), Text('Contómetros')],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: 'Ayuda',
            icon: const Icon(Icons.help_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _scan,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text(
                    'Equipos cercanos',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Busca y administra contómetros autorizados mediante Bluetooth.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _isScanning ? null : _scan,
                    icon: _isScanning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bluetooth_searching_rounded),
                    label: Text(
                      _isScanning ? 'Buscando equipos…' : 'Buscar contómetros',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'DISPOSITIVOS ENCONTRADOS',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Text(
                        '${_devices.length} equipos',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._devices.map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DeviceTile(
                        device: device,
                        onTap: () => _openDevice(device),
                      ),
                    ),
                  ),
                  if (_devices.isEmpty && !_isScanning) const _EmptyDevices(),
                  const SizedBox(height: 8),
                  const _SecurityNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.speed_rounded, color: AppColors.blue, size: 22),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final ContometerDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signal = device.rssi >= -60
        ? ('Excelente', AppColors.success, Icons.signal_cellular_alt_rounded)
        : device.rssi >= -75
        ? ('Buena', AppColors.warning, Icons.network_cell_rounded)
        : ('Débil', AppColors.danger, Icons.signal_cellular_alt_1_bar_rounded);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.directions_car_filled_rounded,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${device.id}  ·  ${device.rssi} dBm',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StatusPill(
                    label: signal.$1,
                    icon: signal.$3,
                    color: signal.$2,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: AppColors.blue, size: 21),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Solo se muestran equipos con el identificador autorizado de Contómetro.',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.blueSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bluetooth_searching_rounded,
              color: AppColors.blue,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aún no encontramos equipos',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enciende el contómetro y toca “Buscar contómetros”.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ConnectingDialog extends StatelessWidget {
  const _ConnectingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Conectando con el contómetro…')),
        ],
      ),
    );
  }
}
