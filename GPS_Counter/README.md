# Contómetro vehicular GPS para ESP32

Firmware desarrollado con ESP-IDF para un ESP32 clásico. El equipo utiliza la velocidad reportada por un receptor GPS Quectel L80-R para detectar eventos de exceso de velocidad, acumularlos en memoria no volátil y mostrarlos en un display de tres dígitos.

Esta versión corresponde al firmware actualmente utilizado en los contómetros instalados en los vehículos.

## Funcionamiento

Al encenderse, el dispositivo:

1. Inicializa la memoria NVS del ESP32.
2. Configura la UART y el pin de reset del GPS.
3. Inicializa el display, el buzzer y el LED de estado.
4. Solicita al GPS una frecuencia de actualización de 5 Hz y las sentencias NMEA RMC y GGA.
5. Recupera de NVS el contador acumulado.
6. Inicia las tareas de lectura GPS, supervisión de velocidad y multiplexación del display.
7. Inicializa NimBLE, anuncia el servicio del contómetro y publica su estado cada segundo.

El control de velocidad utiliza tres estados y confirmación temporal:

| Estado | Entrada | Salida | Aviso acústico |
| --- | --- | --- | --- |
| Normal | Velocidad menor de 27 km/h | Pasa a precaución después de 1 s a 27 km/h o más | Silencio |
| Precaución | 27 km/h o más durante 1 s | Regresa a normal por debajo de 25 km/h durante 1.5 s | Un bip corto cada 2.5 s |
| Exceso | Más de 30 km/h durante 1 s | Sale del exceso por debajo de 28 km/h durante 1.5 s | Patrón `bi-bi`, pausa, `bi-bi` |

Los umbrales de salida distintos de los de entrada forman la **histéresis**. Así se evita cambiar repetidamente de estado por pequeñas oscilaciones del GPS alrededor de 30 km/h.

Cuando se confirma la transición desde normal o precaución hacia exceso:

- Se registra un nuevo evento.
- El contador se guarda inmediatamente en NVS.
- El display muestra el nuevo total.
- El buzzer emite una confirmación y mantiene el patrón de alerta mientras continúa el exceso de velocidad.

Una permanencia continua en exceso genera un solo evento. Para permitir otro evento, el vehículo debe bajar de 28 km/h durante al menos 1.5 segundos y posteriormente volver a superar 30 km/h durante un segundo.

El GPS también aplica un umbral de movimiento de **5 km/h**. Las velocidades inferiores se consideran cero para reducir falsos movimientos producidos por la variación normal del GPS cuando el vehículo está detenido.

## Hardware y conexiones

### GPS Quectel L80-R

| Señal | GPIO del ESP32 | Descripción |
| --- | ---: | --- |
| UART TX | GPIO 25 | Transmisión del ESP32 hacia el GPS |
| UART RX | GPIO 26 | Recepción de datos NMEA |
| RESET | GPIO 23 | Reset del módulo GPS, activo en nivel bajo |

La comunicación utiliza `UART1`, 9600 baudios, 8 bits de datos, sin paridad y un bit de parada.

### Display de tres dígitos

El display utiliza cuatro salidas BCD conectadas a un decodificador externo y tres líneas para seleccionar los dígitos mediante multiplexación.

| Función | GPIO |
| --- | ---: |
| BCD bit 0 | GPIO 2 |
| BCD bit 1 | GPIO 4 |
| BCD bit 2 | GPIO 13 |
| BCD bit 3 | GPIO 33 |
| Dígito 1 | GPIO 18 |
| Dígito 2 | GPIO 19 |
| Dígito 3 | GPIO 21 |
| Punto decimal, reservado | GPIO 14 |

El valor visible está limitado al intervalo de `000` a `999`. El contador interno puede seguir aumentando aunque el display permanezca en `999`.

### Indicadores

| Dispositivo | GPIO | Lógica |
| --- | ---: | --- |
| Buzzer | GPIO 15 | Activo en nivel bajo |
| LED de estado | GPIO 22 | Activo en nivel alto |

> **Precaución de hardware:** GPIO2 y GPIO15 participan en la configuración de arranque del ESP32 clásico. Los circuitos externos no deben forzar niveles incompatibles durante el encendido o el reset.

## Organización del proyecto

```text
GPS_Counter/
├── CMakeLists.txt
├── sdkconfig
├── sdkconfig.defaults
├── README.md
└── main/
    ├── main.c
    ├── CMakeLists.txt
    ├── partitions.csv
    ├── drivers/
    │   ├── buzzer_driver.c
    │   └── led_driver.c
    ├── modules/
    │   ├── ble_contometer.c
    │   ├── gps_l80r.c
    │   ├── monitor_velocidad.c
    │   └── serial_command.c
    └── screens/
        └── display_7seg.c
```

- `main.c`: inicialización del sistema y creación de tareas.
- `gps_l80r`: UART, recepción NMEA, checksum, parser RMC/GGA y datos del GPS.
- `monitor_velocidad`: detección de eventos, alarma y persistencia en NVS.
- `ble_contometer`: servidor GATT NimBLE, advertising, telemetría y configuración desde la app.
- `serial_command`: recepción y validación de la trama de mantenimiento por UART0.
- `display_7seg`: control BCD y multiplexación del display.
- `buzzer_driver` y `led_driver`: control de las salidas de estado.

## Tareas FreeRTOS

| Tarea | Pila | Prioridad | Función |
| --- | ---: | ---: | --- |
| `task_gps_read_and_parse` | 4096 bytes | 5 | Lee la UART, reconstruye sentencias NMEA y actualiza los datos GPS |
| `task_monitor_velocidad` | 4096 bytes | 4 | Evalúa el umbral, cuenta eventos, guarda NVS y controla el buzzer |
| `task_display_7seg` | 4096 bytes | 3 | Multiplexa continuamente los tres dígitos; fijada al núcleo 1 |

## Configuración principal

Los valores actuales se encuentran en el código fuente:

| Parámetro | Valor | Ubicación |
| --- | ---: | --- |
| Umbral de exceso | 30 km/h | `main/modules/monitor_velocidad.c` |
| Entrada de prealerta | 27 km/h | 3 km/h por debajo del umbral de exceso |
| Salida de prealerta | 25 km/h | 2 km/h por debajo de su entrada |
| Salida del exceso | 28 km/h | 2 km/h por debajo del umbral de exceso |
| Confirmación de entrada | 1 segundo | `main/modules/monitor_velocidad.c` |
| Confirmación de salida | 1.5 segundos | `main/modules/monitor_velocidad.c` |
| Intervalo de prealerta | 2.5 segundos | `main/modules/monitor_velocidad.c` |
| Vigencia máxima de datos GPS | 1.5 segundos | `main/modules/monitor_velocidad.c` |
| Umbral de movimiento | 5 km/h | `main/modules/gps_l80r.c` |
| Frecuencia solicitada al GPS | 5 Hz | `main/main.c` |
| Velocidad UART | 9600 baudios | `main/modules/gps_l80r.c` |
| Máximo mostrado | 999 eventos | `main/screens/display_7seg.c` |

Durante el desarrollo el umbral principal puede ajustarse en ejecución mediante:

```c
monitor_velocidad_set_umbral(30.0);
gps_set_umbral_movimiento(5.0);
```

Los demás umbrales se desplazan automáticamente con el principal. Por ejemplo, al configurar 30 km/h se obtienen 27 km/h para entrar en prealerta, 25 km/h para salir de ella y 28 km/h para abandonar el estado de exceso.

## Compilación y grabación

Se necesita una instalación funcional de ESP-IDF o el devcontainer incluido en el repositorio.

Desde una terminal con el entorno de ESP-IDF cargado:

```bash
idf.py set-target esp32
idf.py build
idf.py -p PUERTO flash monitor
```

Ejemplos habituales de `PUERTO`:

- Windows: `COM5`
- Linux: `/dev/ttyUSB0`

Para salir del monitor serie se utiliza `Ctrl+]`.

La configuración actual selecciona un ESP32 clásico con flash de 16 MB y una tabla personalizada con dos particiones OTA de 2400 KB. La funcionalidad de actualización OTA todavía no está implementada en la aplicación.

## Persistencia del contador

El contador se almacena en el namespace NVS `almacen`, con la clave `eventos`. Solamente se escribe cuando se detecta un evento nuevo o cuando se solicita un reinicio del contador, evitando escrituras continuas mientras el vehículo permanece sobre el umbral.

Para reiniciarlo desde el firmware:

```c
monitor_velocidad_reset_contador();
```

Esta función pone el contador y el display en cero, actualiza NVS y emite una confirmación corta con el buzzer.

## Reinicio mediante UART0

El contador puede reiniciarse sin borrar toda la memoria ni volver a grabar el firmware. La consola UART0 recibe una trama binaria de seis bytes a 115200 baudios, 8 bits de datos, sin paridad y un bit de parada.

Trama de reinicio:

```text
A5 5A 01 00 00 FE
```

| Byte | Valor | Descripción |
| ---: | ---: | --- |
| 0 | `A5` | Primera cabecera |
| 1 | `5A` | Segunda cabecera |
| 2 | `01` | Comando de reinicio |
| 3 | `00` | Valor, byte alto |
| 4 | `00` | Valor, byte bajo |
| 5 | `FE` | Checksum XOR de los cinco bytes anteriores |

Para enviarla desde un asistente serial:

1. Abrir el puerto del ESP32 a `115200`, `8N1`.
2. Activar el modo de envío hexadecimal (`HEX send`).
3. Escribir `A5 5A 01 00 00 FE`.
4. Enviar una sola vez.
5. Comprobar que el display cambie a `000` y que la consola confirme el reinicio.

El firmware descarta tramas con cabecera, comando, valor o checksum incorrectos. Una trama válida entrega la solicitud a la tarea del monitor, que coloca el contador en cero, guarda el nuevo valor en NVS y actualiza el display. No se debe activar el envío periódico para este comando.

## Aplicación móvil mediante BLE

El ESP32 anuncia un servicio Bluetooth Low Energy con un nombre inicial generado a partir de su dirección (`CONTOMETRO-XXXX`). El nombre puede cambiarse desde la aplicación y queda almacenado en el namespace NVS `ble_cfg`.

| Recurso | UUID | Operación |
| --- | --- | --- |
| Servicio | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10001` | Se incluye en el advertising para filtrar contómetros |
| Estado | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10002` | Read/Notify |
| Comando | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10003` | Write |
| Nombre | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10004` | Read/Write, máximo 24 bytes UTF-8 |

La característica de estado notifica cada segundo una trama de 10 bytes little-endian:

| Byte | Contenido |
| ---: | --- |
| 0 | Versión del protocolo, actualmente `01` |
| 1–2 | Contador `uint16_t` |
| 3–4 | Velocidad en décimas de km/h |
| 5–6 | Umbral de exceso en décimas de km/h |
| 7 | Flags; bit 0 indica fix GPS válido y reciente |
| 8 | Número de satélites |
| 9 | Estado: 0 normal, 1 precaución, 2 exceso |

Comandos BLE:

```text
01          Reiniciar contador
02 LL HH    Mostrar HHLL en el display durante 5 segundos, sin modificar NVS
```

El reinicio UART0 sigue funcionando independientemente de BLE.

Los datos operativos que muestra la aplicación —conductor, placa, ruta y turno— son actualmente locales a la app. El firmware todavía no define una característica BLE ni claves NVS para almacenarlos.

> **Seguridad:** esta primera integración no exige autenticación BLE. Antes de desplegarla en una flota se debe habilitar emparejamiento seguro o autenticación de aplicación para impedir escrituras de terceros cercanos.

## Estado de validación

- Compilación completa con ESP-IDF 5.5.4: correcta.
- Binario de aplicación generado: `build/contometro_vehicular.bin`.
- Lógica BLE y contrato compartido con la app Flutter: implementados.
- Prueba física completa teléfono–ESP32: pendiente después de grabar esta versión en un equipo.

Antes de desplegar, la prueba física debe comprobar telemetría, prueba de display, cambio de nombre, reinicio BLE, reinicio UART0 y persistencia tras apagar y encender.

## Diagnóstico por consola

Los mensajes del monitor serie permiten distinguir varios estados:

- GPS sin entregar tramas.
- Recepción de NMEA sin sentencias RMC.
- RMC recibida pero sin fix válido.
- Última RMC válida demasiado antigua; su velocidad se descarta después de 1.5 segundos sin datos nuevos.
- Fix válido con velocidad, coordenadas, altitud, HDOP y satélites.
- Detección y almacenamiento de un nuevo evento.

Para una prueba en banco:

1. Verificar el encendido del equipo y el valor recuperado en el display.
2. Confirmar en consola la llegada de sentencias RMC y GGA.
3. Esperar un fix válido y comprobar satélites y HDOP.
4. Configurar temporalmente umbrales bajos si se necesita probar sin circular a 30 km/h.
5. Restaurar los umbrales de operación antes de desplegar el firmware.
6. Reiniciar el ESP32 y confirmar que el contador permanece almacenado.

## Consideraciones de mantenimiento

- Esta es una versión desplegada en vehículos. Cualquier modificación debe validarse primero en banco y después en una prueba controlada.
- Conservar un binario identificado de la versión estable antes de actualizar equipos instalados.
- Comprobar el cableado, la alimentación y la antena antes de atribuir la ausencia de fix al firmware.
- Evitar conectar simultáneamente otra rutina que consuma la misma UART del GPS.
- Si se cambia el mapa de pines, revisar especialmente los pines de arranque del ESP32.
- El contador representa cruces del umbral, no el tiempo total ni la distancia recorrida por encima del límite.

## Mejoras previstas

Para futuras versiones se recomienda evaluar:

- Intercambio atómico de una instantánea GPS entre tareas.
- Parser NMEA que conserve campos vacíos y admita identificadores `GP` y `GN`.
- Validación de respuestas del GPS a los comandos de configuración.
- Registro de la versión de firmware en los mensajes de arranque.
- Pruebas unitarias del parser y de la lógica del contador.
- Autenticación o bonding BLE para proteger los comandos de escritura.
- Persistencia opcional en NVS de los datos operativos definidos desde la app.

Estas mejoras deben incorporarse conservando el comportamiento comprobado de los equipos que ya están en servicio.
