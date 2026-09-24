# App Contómetro

Aplicación móvil Flutter para descubrir, supervisar y configurar por Bluetooth Low Energy (BLE) los contómetros vehiculares basados en ESP32 del proyecto `GPS_Counter`.

La interfaz utiliza una paleta azul, marfil, coral y durazno, con tarjetas redondeadas y una navegación pensada para uso rápido junto al vehículo.

## Funciones disponibles

- Escaneo BLE real, filtrado por el servicio propio del contómetro.
- Lista de equipos cercanos ordenada por intensidad de señal RSSI.
- Conexión directa con el ESP32 seleccionado.
- Lectura en vivo de contador, velocidad, límite, fix GPS, satélites y estado de velocidad.
- Reinicio del contador persistente, con confirmación previa.
- Prueba temporal del display entre `000` y `999`, sin modificar el contador.
- Cambio del nombre BLE del equipo; el firmware lo guarda en NVS.
- Formulario local de conductor, placa, ruta y turno.

> Los datos de conductor, placa, ruta y turno solamente viven en memoria mientras la app está abierta. Todavía no se envían ni se guardan en el ESP32.

## Pantallas

1. **Equipos cercanos:** solicita permisos, inicia la búsqueda BLE y muestra solamente dispositivos compatibles.
2. **Resumen:** presenta telemetría recibida del contómetro en tiempo real.
3. **Configuración:** permite probar el display, renombrar el dispositivo y reiniciar el contador.
4. **Datos operativos:** permite completar información complementaria para el reporte visual de la app.

## Requisitos

- Flutter `3.44.5` o una versión compatible con Dart `^3.12.2`.
- Android o iOS con Bluetooth Low Energy.
- Un ESP32 grabado con el firmware ubicado en `../GPS_Counter`.
- Bluetooth encendido y permisos concedidos a la aplicación.

Dependencias principales:

- `flutter_reactive_ble 5.5.0`: exploración, conexión y comunicación GATT.
- `reactive_ble_mobile 5.5.0`: implementación móvil fijada para mantener compatibilidad con Android API 36.
- `permission_handler 12.0.3`: permisos Bluetooth y ubicación cuando corresponde.

Estas versiones están fijadas intencionalmente. Las versiones Android inmediatamente posteriores requieren `compileSdk 37`, mientras Flutter 3.44.x utiliza API 36 y Android Gradle Plugin 9.0.1 recomienda como máximo API 36.

## Ejecutar la aplicación

```bash
flutter pub get
flutter run
```

Para elegir un dispositivo concreto:

```bash
flutter devices
flutter run -d ID_DEL_DISPOSITIVO
```

## Permisos

### Android

- Android 12 o superior utiliza `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT`.
- Android 11 o anterior puede solicitar ubicación para descubrir equipos BLE.
- El manifiesto declara que el teléfono debe disponer de BLE.

### iOS

Las descripciones de uso de Bluetooth están incluidas en `ios/Runner/Info.plist`. iOS presenta su propio diálogo de autorización.

## Protocolo BLE

| Recurso | UUID | Operación |
| --- | --- | --- |
| Servicio | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10001` | Descubrimiento |
| Estado | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10002` | Lectura y notificación |
| Comandos | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10003` | Escritura |
| Nombre | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10004` | Lectura y escritura |

### Estado del contómetro

El ESP32 envía cada segundo una trama binaria versionada de 10 bytes, en little-endian:

| Byte | Contenido |
| ---: | --- |
| 0 | Versión del protocolo; actualmente `01` |
| 1–2 | Contador `uint16` |
| 3–4 | Velocidad en décimas de km/h |
| 5–6 | Umbral de exceso en décimas de km/h |
| 7 | Flags; bit 0 indica fix GPS válido y reciente |
| 8 | Número de satélites |
| 9 | Estado: `0` normal, `1` precaución, `2` exceso |

### Comandos

```text
01          Reiniciar el contador persistente
02 LL HH    Mostrar el valor HHLL durante 5 segundos, sin modificar NVS
```

El nombre admite hasta 24 bytes UTF-8. El nuevo valor se guarda en el ESP32 y se refleja en el advertising después de desconectarse.

## Organización principal

```text
lib/
├── main.dart
├── models/
│   └── contometer_device.dart
├── screens/
│   ├── device_scan_screen.dart
│   └── device_workspace_screen.dart
├── services/
│   └── ble_contometer_service.dart
├── theme/
│   └── app_theme.dart
└── widgets/
    ├── app_card.dart
    └── status_pill.dart
```

- `ble_contometer_service.dart`: UUID, codificación del protocolo, escaneo, conexión y sesión BLE.
- `device_scan_screen.dart`: permisos, descubrimiento y selección de equipos.
- `device_workspace_screen.dart`: telemetría, configuración y acciones remotas.
- `app_theme.dart`: colores, tipografía y estilos visuales.

## Validación

```bash
flutter analyze
flutter test
```

Si Gradle conserva una caché anterior de los plugins, ejecutar antes de volver a instalar:

```bash
flutter clean
flutter pub get
flutter run
```

Estado comprobado durante el desarrollo:

- Análisis estático: sin incidencias.
- Pruebas de widgets: aprobadas.
- Integración Dart con el protocolo BLE: implementada.
- Prueba física completa teléfono–ESP32: pendiente después de grabar el firmware en un equipo.
- Generación del APK desde el entorno automatizado aislado: no verificable porque su sandbox impide la conexión loopback interna de Java/Gradle. La compilación debe ejecutarse desde una terminal normal de VS Code, PowerShell o Android Studio.

## Seguridad y despliegue

La primera versión BLE no exige autenticación ni emparejamiento. Un dispositivo cercano compatible podría intentar escribir en las características de configuración. Antes de usar la solución en producción se debe añadir bonding seguro o autenticación a nivel de aplicación.

También se recomienda validar en banco el reinicio, el cambio de nombre y la prueba de display antes de operar con un vehículo.
