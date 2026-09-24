#ifndef BLE_CONTOMETER_H
#define BLE_CONTOMETER_H

#include "esp_err.h"

// Servicio: 7b1e4000-7a2b-4c9d-ae55-3f49c2a10001
// Estado:   7b1e4000-7a2b-4c9d-ae55-3f49c2a10002 (read/notify)
// Comando:  7b1e4000-7a2b-4c9d-ae55-3f49c2a10003 (write)
// Nombre:   7b1e4000-7a2b-4c9d-ae55-3f49c2a10004 (read/write)

esp_err_t ble_contometer_init(void);

#endif
