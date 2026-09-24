#ifndef SERIAL_COMMAND_H
#define SERIAL_COMMAND_H

#include "esp_err.h"

// Inicializa la recepcion de comandos binarios por la consola UART0.
esp_err_t serial_command_init(void);

#endif // SERIAL_COMMAND_H
