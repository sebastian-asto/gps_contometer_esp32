#ifndef MONITOR_VELOCIDAD_H
#define MONITOR_VELOCIDAD_H

#include <stdint.h>
#include <stdbool.h>

typedef enum {
    VELOCIDAD_NORMAL = 0,
    VELOCIDAD_PRECAUCION,
    VELOCIDAD_EXCESO
} estado_velocidad_t;

// GETTERS
double monitor_velocidad_get_umbral(void);
uint16_t monitor_velocidad_get_contador_eventos(void);
bool monitor_velocidad_ultimo_fix_valido(void);
estado_velocidad_t monitor_velocidad_get_estado(void);

// SETTERS
void monitor_velocidad_set_umbral(double nuevo_umbral);
void monitor_velocidad_reset_contador(void);
bool monitor_velocidad_solicitar_reset(void);
bool monitor_velocidad_solicitar_prueba_display(uint16_t valor);

// TAREA PRINCIPAL
void task_monitor_velocidad(void *pvParameters);

#endif
