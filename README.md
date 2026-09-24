# Contómetro GPS

Sistema vehicular para detectar y contar eventos de exceso de velocidad. Está compuesto por un firmware para ESP32 con GPS, display y avisos acústicos, y una aplicación Flutter que se comunica con el equipo mediante Bluetooth Low Energy.

## Componentes del proyecto

```text
Contometer_GPS/
├── README.md                 Documentación general
├── pantallas_app.png         Boceto inicial de la aplicación
├── GPS_Counter/              Firmware ESP-IDF para el ESP32
│   ├── README.md             Hardware, lógica, UART0, BLE y compilación
│   └── main/
└── app_contometer/           Aplicación móvil Flutter
    ├── README.md             Instalación, pantallas y protocolo BLE
    └── lib/
```

| Componente | Tecnología | Responsabilidad |
| --- | --- | --- |
| `GPS_Counter` | C, ESP-IDF, FreeRTOS y NimBLE | Lee el GPS, aplica histéresis, controla display/buzzer y conserva el contador en NVS |
| `app_contometer` | Flutter y Dart | Descubre equipos, muestra telemetría y envía comandos de configuración por BLE |

## Funcionamiento general

1. El GPS Quectel L80-R entrega velocidad y datos de posición al ESP32.
2. El firmware descarta datos GPS inválidos o antiguos y aplica una máquina de estados con confirmación temporal e histéresis.
3. Al confirmar un exceso de velocidad se incrementa una sola vez el contador y se guarda en NVS.
4. El display presenta el total acumulado y el buzzer diferencia la proximidad al límite del exceso confirmado.
5. El ESP32 publica por BLE su estado una vez por segundo.
6. La app descubre el servicio del contómetro, se conecta y permite consultar o configurar el equipo.

## Estados de velocidad e histéresis

Con el límite principal configurado en 30 km/h:

| Estado | Entrada confirmada | Salida confirmada | Buzzer |
| --- | --- | --- | --- |
| Normal | Menos de 27 km/h | — | Silencio |
| Precaución | 27 km/h o más durante 1 s | Menos de 25 km/h durante 1.5 s | Un bip corto cada 2.5 s |
| Exceso | Más de 30 km/h durante 1 s | Menos de 28 km/h durante 1.5 s | Patrón `bi-bi`, pausa, `bi-bi` |

La diferencia entre los umbrales de entrada y salida evita cambios rápidos de estado cuando la medición oscila cerca del límite. Una permanencia continua en exceso genera un solo evento; para contar otro, el vehículo debe salir primero del estado de exceso.

## Comunicación y configuración

El proyecto ofrece dos canales independientes:

- **BLE:** telemetría, reinicio del contador, prueba del display y cambio de nombre del equipo.
- **UART0:** reinicio de mantenimiento mediante la trama hexadecimal `A5 5A 01 00 00 FE`, a `115200 8N1`.

Servicio BLE principal:

```text
7b1e4000-7a2b-4c9d-ae55-3f49c2a10001
```

| Característica | Terminación UUID | Uso |
| --- | --- | --- |
| Estado | `0002` | Read/Notify: contador, velocidad, límite, GPS, satélites y estado |
| Comandos | `0003` | Write: reinicio y prueba del display |
| Nombre | `0004` | Read/Write: nombre BLE persistente |

El detalle byte a byte está documentado tanto en `GPS_Counter/README.md` como en `app_contometer/README.md`.

## Puesta en marcha

### 1. Compilar y grabar el firmware

Se requiere ESP-IDF con soporte para ESP32 clásico:

```bash
cd GPS_Counter
idf.py set-target esp32
idf.py build
idf.py -p PUERTO flash monitor
```

Antes de continuar, confirmar en consola que llegan sentencias RMC/GGA y que el equipo anuncia un nombre similar a `CONTOMETRO-XXXX`.

### 2. Ejecutar la aplicación

Se requiere Flutter y un teléfono Android o iOS con BLE:

```bash
cd app_contometer
flutter pub get
flutter analyze
flutter test
flutter run
```

En la app, conceder permisos Bluetooth, buscar equipos, seleccionar el contómetro y comprobar que el estado se actualice cada segundo.

## Prueba de integración recomendada

1. Grabar el firmware y reiniciar el ESP32.
2. Confirmar el nombre BLE y el valor inicial del display.
3. Conectar la app y verificar velocidad, contador, GPS y satélites.
4. Enviar un valor de prueba al display y confirmar que el contador almacenado no cambie.
5. Cambiar el nombre, desconectar y comprobar el nuevo nombre en otra búsqueda.
6. Reiniciar el contador desde la app y después mediante UART0.
7. Probar los estados normal, precaución y exceso en banco o en un entorno controlado.
8. Reiniciar el equipo y confirmar la persistencia en NVS.

## Estado actual

- Firmware ESP32 con GPS, NVS, display, buzzer, histéresis, UART0 y BLE: implementado.
- Compilación del firmware con ESP-IDF 5.5.4: completada correctamente.
- App Flutter con descubrimiento, conexión y configuración BLE real: implementada.
- `flutter analyze` y `flutter test`: completados correctamente.
- Prueba física completa teléfono–ESP32: pendiente.
- APK Android desde el entorno automatizado aislado: no verificable porque su sandbox impide la conexión loopback interna de Java/Gradle. La compilación debe ejecutarse desde una terminal normal de VS Code, PowerShell o Android Studio.

## Seguridad

La integración BLE actual no exige autenticación ni emparejamiento. Esto es apropiado para las primeras pruebas de banco, pero no para un despliegue comercial. Antes de instalarla en una flota se debe habilitar bonding seguro o autenticación de aplicación y repetir las pruebas de integración.

## Documentación detallada

- [`GPS_Counter/README.md`](GPS_Counter/README.md): conexiones, tareas, histéresis, buzzer, persistencia, UART0, BLE, compilación y diagnóstico.
- [`app_contometer/README.md`](app_contometer/README.md): interfaz, permisos, protocolo BLE, ejecución, pruebas y limitaciones actuales.
