import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contometer_device.dart';
import '../services/ble_contometer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/status_pill.dart';

class DeviceWorkspaceScreen extends StatefulWidget {
  const DeviceWorkspaceScreen({super.key, required this.session});

  final BleContometerSession session;

  @override
  State<DeviceWorkspaceScreen> createState() => _DeviceWorkspaceScreenState();
}

class _DeviceWorkspaceScreenState extends State<DeviceWorkspaceScreen> {
  late ContometerDevice _device;
  late ContometerStatus _status;
  StreamSubscription<ContometerStatus>? _statusSubscription;
  int _selectedIndex = 0;
  final Map<String, String> _metadata = {
    'Conductor': 'Luis Mendoza',
    'Placa': 'V7P-218',
    'Ruta': 'Villa El Salvador',
    'Turno': 'Mañana',
  };

  @override
  void initState() {
    super.initState();
    _device = widget.session.device;
    _status = widget.session.latestStatus;
    _statusSubscription = widget.session.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        _device = widget.session.device;
      });
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _updateDevice(ContometerDevice updated) =>
      setState(() => _device = updated);

  void _close() => Navigator.of(context).pop(_device);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${_device.id} · Conectado',
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(
              Icons.bluetooth_connected_rounded,
              color: AppColors.blue,
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _ReportView(
            device: _device,
            status: _status,
            metadata: _metadata,
            onMetadataChanged: () => setState(() {}),
          ),
          _ConfigurationView(
            device: _device,
            session: widget.session,
            onChanged: _updateDevice,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) =>
            setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Resumen',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Configurar',
          ),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.device,
    required this.status,
    required this.metadata,
    required this.onMetadataChanged,
  });

  final ContometerDevice device;
  final ContometerStatus status;
  final Map<String, String> metadata;
  final VoidCallback onMetadataChanged;

  Future<void> _addParameter(BuildContext context) async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo dato del vehículo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'Nombre del dato'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == true && keyController.text.trim().isNotEmpty) {
      metadata[keyController.text.trim()] = valueController.text.trim().isEmpty
          ? 'Sin definir'
          : valueController.text.trim();
      onMetadataChanged();
    }
    keyController.dispose();
    valueController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speedState = switch (status.speedState) {
      1 => ('Precaución', Icons.notifications_active_outlined, AppColors.peach),
      2 => ('Exceso', Icons.warning_rounded, AppColors.coral),
      _ => ('Velocidad normal', Icons.check_rounded, AppColors.success),
    };

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const StatusPill(
                    label: 'En línea',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
                  StatusPill(
                    label: status.gpsValid
                        ? 'GPS · ${status.satellites} satélites'
                        : 'GPS sin posición',
                    icon: status.gpsValid
                        ? Icons.gps_fixed_rounded
                        : Icons.gps_off_rounded,
                    color: status.gpsValid
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  StatusPill(
                    label: speedState.$1,
                    icon: speedState.$2,
                    color: speedState.$3,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Row(
                  children: [
                    const _MetricIcon(
                      icon: Icons.navigation_rounded,
                      color: AppColors.coral,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Velocidad actual',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                    Text(
                      '${status.speedKmh.toStringAsFixed(1)} km/h',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                color: AppColors.blue,
                child: Column(
                  children: [
                    const Text(
                      'EVENTOS DE EXCESO REGISTRADOS',
                      style: TextStyle(
                        color: Color(0xFFB9CDE1),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status.counter.toString().padLeft(3, '0'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Desde el último reinicio',
                      style: TextStyle(color: Color(0xFFB9CDE1), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Datos del vehículo',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => _addParameter(context),
                    tooltip: 'Agregar parámetro',
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final entry in metadata.entries)
                      _DataRow(
                        label: entry.key,
                        value: entry.value,
                        showDivider: entry.key != metadata.keys.last,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Row(
                  children: [
                    const _MetricIcon(
                      icon: Icons.speed_rounded,
                      color: AppColors.orange,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Límite configurado',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                    Text(
                      '${status.speedLimitKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigurationView extends StatefulWidget {
  const _ConfigurationView({
    required this.device,
    required this.session,
    required this.onChanged,
  });

  final ContometerDevice device;
  final BleContometerSession session;
  final ValueChanged<ContometerDevice> onChanged;

  @override
  State<_ConfigurationView> createState() => _ConfigurationViewState();
}

class _ConfigurationViewState extends State<_ConfigurationView> {
  late final TextEditingController _nameController;
  final TextEditingController _testValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
  }

  @override
  void didUpdateWidget(covariant _ConfigurationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.name != widget.device.name &&
        _nameController.text != widget.device.name) {
      _nameController.text = widget.device.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _testValueController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetCounter() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.restart_alt_rounded,
          color: AppColors.danger,
          size: 34,
        ),
        title: const Text('¿Reiniciar contador?'),
        content: const Text(
          'El valor almacenado en el equipo cambiará a 000. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.session.resetCounter();
        _showMessage('Reinicio enviado al contómetro');
      } catch (error) {
        _showMessage('No se pudo reiniciar: $error');
      }
    }
  }

  Future<void> _applyTestValue() async {
    final value = int.tryParse(_testValueController.text);
    if (value == null || value < 0 || value > 999) {
      _showMessage('Ingresa un valor entre 0 y 999');
      return;
    }
    try {
      await widget.session.testDisplay(value);
      _showMessage('El display mostrará $value durante 5 segundos');
      _testValueController.clear();
    } catch (error) {
      _showMessage('No se pudo enviar la prueba: $error');
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('El nombre no puede estar vacío');
      return;
    }
    try {
      await widget.session.rename(name);
      widget.onChanged(widget.session.device);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      _showMessage('Nombre guardado en el contómetro');
    } catch (error) {
      _showMessage('No se pudo guardar el nombre: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                'Configuración',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Administra el equipo conectado.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      icon: Icons.pin_outlined,
                      title: 'Prueba del display',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Muestra temporalmente un valor sin modificar el contador almacenado.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _testValueController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Valor de prueba',
                        hintText: '000 – 999',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _applyTestValue,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Enviar valor de prueba'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      icon: Icons.badge_outlined,
                      title: 'Nombre del dispositivo',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Este nombre aparecerá durante la búsqueda de contómetros.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 36,
                      decoration: const InputDecoration(
                        labelText: 'Nombre visible',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saveName,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar nombre'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      icon: Icons.restart_alt_rounded,
                      title: 'Reinicio del contador',
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Valor actual: ${widget.device.counter.toString().padLeft(3, '0')} eventos',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      ),
                      onPressed: _resetCounter,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Reiniciar contador'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.color = AppColors.blue,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    required this.value,
    required this.showDivider,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 18, endIndent: 18),
      ],
    );
  }
}

class _MetricIcon extends StatelessWidget {
  const _MetricIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color),
    );
  }
}
