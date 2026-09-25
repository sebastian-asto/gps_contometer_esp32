# Simulador BLE para ESP32 clásico de 4 MB

Firmware de banco para probar `app_contometer` con una placa ESP32-WROOM-32 sin conectar GPS, display ni buzzer. Es un proyecto ESP-IDF independiente y no modifica el comportamiento del firmware vehicular ubicado en la carpeta superior.

## Qué simula

- El mismo servicio, características y trama BLE del contómetro real.
- Nombre inicial `CONTOMETRO-TEST-XXXX`, persistente y modificable desde la app.
- Fix GPS válido y 9 satélites simulados.
- Límite fijo de 30 km/h.
- Ciclo automático de 36 segundos:

| Segundos | Velocidad | Estado |
| ---: | ---: | --- |
| 0–4 | 0 km/h | Normal |
| 5–9 | 24 km/h | Normal |
| 10–15 | 28 km/h | Precaución |
| 16–25 | 32 km/h | Exceso |
| 26–30 | 27 km/h | Precaución |
| 31–35 | 23 km/h | Normal |

Cada entrada al estado de exceso incrementa el contador y lo guarda en NVS. El reinicio enviado desde la app coloca el contador en cero. La prueba de display se acepta y se imprime en la consola, pero no controla pines porque esta variante no necesita hardware adicional.

## Compatibilidad

- ESP32 clásico / ESP32-WROOM-32.
- Flash de 4 MB.
- ESP-IDF 5.5.x.
- Aplicación Flutter `app_contometer` sin cambios.

## Compilar y grabar

Desde una terminal ESP-IDF:

```bash
cd GPS_Counter/test_ble_4mb
idf.py set-target esp32
idf.py build
idf.py -p COMx flash monitor
```

Reemplazar `COMx` por el puerto de la placa. Para salir del monitor se utiliza `Ctrl+]`.

También se incluye un archivo combinado listo para grabar desde `0x0`:

```text
dist/contometro_ble_test_4mb_merged.bin
```

Puede grabarse con esptool sin indicar por separado bootloader, tabla de particiones y aplicación:

```bash
python -m esptool --chip esp32 --port COMx --baud 460800 erase_flash
python -m esptool --chip esp32 --port COMx --baud 460800 write_flash 0x0 dist/contometro_ble_test_4mb_merged.bin
```

El borrado previo evita que nombres o contadores guardados por otro firmware permanezcan en NVS.

Después de iniciar:

1. Abrir la app y conceder permisos Bluetooth.
2. Pulsar **Buscar contómetros**.
3. Seleccionar `CONTOMETRO-TEST-XXXX`.
4. Observar durante 36 segundos los cambios de velocidad y estado.
5. Probar el cambio de nombre, el valor temporal de display y el reinicio del contador.

## Protocolo

Utiliza los mismos UUID que el firmware real:

| Recurso | UUID |
| --- | --- |
| Servicio | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10001` |
| Estado | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10002` |
| Comandos | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10003` |
| Nombre | `7b1e4000-7a2b-4c9d-ae55-3f49c2a10004` |

Esta versión conserva la misma advertencia de seguridad del prototipo: BLE no requiere autenticación y debe utilizarse solamente para pruebas controladas.

## Binarios verificados

| Archivo | Tamaño | SHA-256 |
| --- | ---: | --- |
| `build/contometro_ble_test_4mb.bin` | 469184 bytes | `6299A94FB928A194137C9BA6B9F61AC8E3E8A41E83B8C60C612DA8A519B38B6B` |
| `dist/contometro_ble_test_4mb_merged.bin` | 534720 bytes | `1D3E77EFFEA13B12BFA09136BC43B91647852DB9D16C1F3894259148C98209C0` |

La imagen combinada fue generada para flash de 4 MB, modo DIO y frecuencia de 40 MHz.
