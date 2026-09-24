#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_log.h>
#include <stdbool.h>
#include <stdint.h>

#include "nvs_flash.h"
#include "nvs.h"

#include "monitor_velocidad.h"
#include "gps_l80r.h"
#include "screens/display_7seg.h"
#include "drivers/buzzer_driver.h"

static const char *TAG = "MONITOR_VEL";

// ===========================================================
//  PARÁMETROS CONFIGURABLES
// ===========================================================
static double umbral_velocidad = 30.0;   // km/h

// Los umbrales secundarios se calculan respecto al umbral de exceso.
// Con el valor predeterminado de 30 km/h:
//   prealerta entra en 27, sale en 25 y exceso sale en 28 km/h.
#define MARGEN_ENTRADA_PREALERTA_KMH  3.0
#define HISTERESIS_PREALERTA_KMH      2.0
#define HISTERESIS_EXCESO_KMH         2.0

#define TIEMPO_CONFIRMAR_ENTRADA_MS   1000
#define TIEMPO_CONFIRMAR_SALIDA_MS    1500
#define INTERVALO_PREALERTA_MS        2500
#define GPS_MAX_AGE_MS                1500

// ===========================================================
//  VARIABLES INTERNAS
// ===========================================================
static uint16_t contador_eventos = 0;
static bool ultimo_fix_valido = false;
static TaskHandle_t monitor_task_handle = NULL;

typedef enum {
    CONFIRMACION_NINGUNA = 0,
    CONFIRMACION_PREALERTA,
    CONFIRMACION_EXCESO,
    CONFIRMACION_NORMAL,
    CONFIRMACION_SALIDA_EXCESO
} tipo_confirmacion_t;

static estado_velocidad_t estado_velocidad = VELOCIDAD_NORMAL;
static tipo_confirmacion_t confirmacion_actual = CONFIRMACION_NINGUNA;
static TickType_t inicio_confirmacion = 0;
static TickType_t ultimo_bip_prealerta = 0;
static TickType_t ts_ultimo_bip_exceso = 0;
static uint8_t contador_bips_exceso = 0;
static uint16_t valor_prueba_display = 0;

#define NOTIFICACION_RESET_CONTADOR (1UL << 0)
#define NOTIFICACION_PRUEBA_DISPLAY (1UL << 1)
#define DURACION_PRUEBA_DISPLAY_MS 5000

// ===========================================================
//  NVS: GUARDAR CONTADOR COMO uint32_t
// ===========================================================
static void guardar_contador_eventos(uint16_t valor)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open("almacen", NVS_READWRITE, &handle);

    if (err == ESP_OK) {
        uint32_t tmp = (uint32_t)valor;
        nvs_set_u32(handle, "eventos", tmp);
        nvs_commit(handle);
        nvs_close(handle);

        ESP_LOGI(TAG, "Contador guardado en NVS: %u", valor);
    } else {
        ESP_LOGE(TAG, "Error al abrir NVS para guardar contador");
    }
}

// ===========================================================
//  NVS: LEER CONTADOR GUARDADO
// ===========================================================
static void leer_contador_guardado_en_nvs(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open("almacen", NVS_READWRITE, &handle);

    if (err == ESP_OK) {
        uint32_t tmp = 0;

        if (nvs_get_u32(handle, "eventos", &tmp) == ESP_OK) {
            contador_eventos = (uint16_t)tmp;
            ESP_LOGI(TAG, "Contador cargado desde NVS: %u", contador_eventos);
        } else {
            contador_eventos = 0;
            ESP_LOGW(TAG, "No existe contador previo, comenzando en 0");
        }

        nvs_close(handle);
    } else {
        ESP_LOGE(TAG, "Error al abrir NVS para leer contador");
    }
}

// ===========================================================
//  GETTERS Y SETTERS
// ===========================================================
double monitor_velocidad_get_umbral(void) {
    return umbral_velocidad;
}

uint16_t monitor_velocidad_get_contador_eventos(void) {
    return contador_eventos;
}

bool monitor_velocidad_ultimo_fix_valido(void) {
    return ultimo_fix_valido;
}

estado_velocidad_t monitor_velocidad_get_estado(void) {
    return estado_velocidad;
}

void monitor_velocidad_set_umbral(double nuevo_umbral) {
    if (nuevo_umbral <= 0.0) {
        ESP_LOGW(TAG, "Umbral invalido: %.2f km/h", nuevo_umbral);
        return;
    }

    umbral_velocidad = nuevo_umbral;
    ESP_LOGI(TAG,"🟢 Nuevo umbral de velocidad establecido a %.2f km/h", umbral_velocidad);
}

void monitor_velocidad_reset_contador(void)
{
    contador_eventos = 0;
    estado_velocidad = VELOCIDAD_NORMAL;
    confirmacion_actual = CONFIRMACION_NINGUNA;
    contador_bips_exceso = 0;
    guardar_contador_eventos(0);

    ESP_LOGW(TAG, "🟢 Contador de eventos reiniciado a 0");
    display_set_number(0);

    buzzer_on();
    vTaskDelay(pdMS_TO_TICKS(100));
    buzzer_off();
}

bool monitor_velocidad_solicitar_reset(void)
{
    if (monitor_task_handle == NULL) {
        return false;
    }

    return xTaskNotify(
        monitor_task_handle,
        NOTIFICACION_RESET_CONTADOR,
        eSetBits
    ) == pdPASS;
}

// ===========================================================
//  PATRÓN DE ALERTA: BI-BI… (pausa) … BI-BI…
// ===========================================================
static double max_cero(double valor)
{
    return valor > 0.0 ? valor : 0.0;
}

bool monitor_velocidad_solicitar_prueba_display(uint16_t valor)
{
    if (monitor_task_handle == NULL || valor > 999) {
        return false;
    }

    valor_prueba_display = valor;
    return xTaskNotify(
        monitor_task_handle,
        NOTIFICACION_PRUEBA_DISPLAY,
        eSetBits
    ) == pdPASS;
}

static double umbral_prealerta_entrada(void)
{
    return max_cero(umbral_velocidad - MARGEN_ENTRADA_PREALERTA_KMH);
}

static double umbral_prealerta_salida(void)
{
    return max_cero(umbral_prealerta_entrada() - HISTERESIS_PREALERTA_KMH);
}

static double umbral_exceso_salida(void)
{
    return max_cero(umbral_velocidad - HISTERESIS_EXCESO_KMH);
}

static void reset_confirmacion(void)
{
    confirmacion_actual = CONFIRMACION_NINGUNA;
}

static bool condicion_confirmada(tipo_confirmacion_t tipo, uint32_t tiempo_ms)
{
    TickType_t ahora = xTaskGetTickCount();

    if (confirmacion_actual != tipo) {
        confirmacion_actual = tipo;
        inicio_confirmacion = ahora;
        return false;
    }

    return (ahora - inicio_confirmacion) >= pdMS_TO_TICKS(tiempo_ms);
}

static void reset_patrones_alarma(void)
{
    ultimo_bip_prealerta = 0;
    ts_ultimo_bip_exceso = 0;
    contador_bips_exceso = 0;
}

// Prealerta discreta: un bip corto cada 2.5 segundos.
static void alerta_precaucion(void)
{
    TickType_t ahora = xTaskGetTickCount();

    if (ultimo_bip_prealerta == 0 ||
        ahora - ultimo_bip_prealerta >= pdMS_TO_TICKS(INTERVALO_PREALERTA_MS)) {
        buzzer_on();
        vTaskDelay(pdMS_TO_TICKS(70));
        buzzer_off();
        ultimo_bip_prealerta = xTaskGetTickCount();
    }
}

static void alerta_bi_bi(void)
{
    TickType_t ahora = xTaskGetTickCount();

    // bip cada 180 ms
    if (contador_bips_exceso < 2) {
        if (ahora - ts_ultimo_bip_exceso > pdMS_TO_TICKS(180)) {

            // beep corto
            buzzer_on();
            vTaskDelay(pdMS_TO_TICKS(70));
            buzzer_off();

            contador_bips_exceso++;
            ts_ultimo_bip_exceso = xTaskGetTickCount();
        }
    }
    else {
        // pausa larga después del BI-BI
        if (ahora - ts_ultimo_bip_exceso > pdMS_TO_TICKS(600)) {
            contador_bips_exceso = 0;   // reiniciar bi-bi
            ts_ultimo_bip_exceso = xTaskGetTickCount();
        }
    }
}

// ===========================================================
//  FUNCIÓN PARA DIAGNOSTICAR ESTADO DEL GPS
// ===========================================================
static bool gps_diagnostico_ok(double vel, bool fix_ok, bool datos_recientes)
{
    uint32_t tramas = gps_get_contador_tramas();
    uint32_t rmc = gps_get_contador_rmc();

    // 1) GPS no conectado
    if (tramas == 0) {
        ESP_LOGW("MONITOR_VEL", "🛑 GPS NO CONECTADO (no llegan tramas)");
        vTaskDelay(pdMS_TO_TICKS(300));
        return false;
    }

    // 2) No llegan tramas RMC
    if (rmc == 0) {
        ESP_LOGW("MONITOR_VEL", "⚠️ GPS CONECTADO → PERO NO LLEGAN TRAMAS RMC");
        vTaskDelay(pdMS_TO_TICKS(300));
        return false;
    }

    // 3) Hay RMC pero sin FIX válido
    if (!fix_ok) {
        ESP_LOGW("MONITOR_VEL", "⚠️ RMC SIN FIX VÁLIDO → Vel %.2f ignorada", vel);
        vTaskDelay(pdMS_TO_TICKS(200));
        return false;
    }

    // 4) El ultimo fix fue valido, pero dejo de llegar informacion nueva.
    if (!datos_recientes) {
        ESP_LOGW("MONITOR_VEL", "GPS SIN DATOS RECIENTES; velocidad ignorada");
        vTaskDelay(pdMS_TO_TICKS(200));
        return false;
    }

    return true; // Todo está OK
}


// ===========================================================
//  Task principal
// ===========================================================
void task_monitor_velocidad(void *pvParameters)
{
    monitor_task_handle = xTaskGetCurrentTaskHandle();
    leer_contador_guardado_en_nvs();
    display_set_number(contador_eventos);
    bool gps_previamente_ok = false;
    bool prueba_display_activa = false;
    TickType_t fin_prueba_display = 0;

    while (1)
    {
        uint32_t notificaciones = 0;
        if (xTaskNotifyWait(0, UINT32_MAX, &notificaciones, 0) == pdTRUE) {
            if ((notificaciones & NOTIFICACION_RESET_CONTADOR) != 0) {
                monitor_velocidad_reset_contador();
                prueba_display_activa = false;
            }
            if ((notificaciones & NOTIFICACION_PRUEBA_DISPLAY) != 0) {
                display_set_number(valor_prueba_display);
                prueba_display_activa = true;
                fin_prueba_display = xTaskGetTickCount() +
                    pdMS_TO_TICKS(DURACION_PRUEBA_DISPLAY_MS);
                ESP_LOGI(TAG, "Prueba de display: %u durante %u ms",
                         valor_prueba_display, DURACION_PRUEBA_DISPLAY_MS);
            }
        }

        if (prueba_display_activa &&
            (int32_t)(xTaskGetTickCount() - fin_prueba_display) >= 0) {
            display_set_number(contador_eventos);
            prueba_display_activa = false;
        }

        double vel = gps_get_speed_kmh();
        bool fix_ok = gps_is_valid();
        bool datos_recientes = gps_data_is_fresh(GPS_MAX_AGE_MS);
        ultimo_fix_valido = fix_ok;

        // DIAGNÓSTICO CENTRALIZADO
        if (!gps_diagnostico_ok(vel, fix_ok, datos_recientes)) {
            if (gps_previamente_ok) {
                buzzer_off();
                reset_patrones_alarma();
            }
            gps_previamente_ok = false;
            reset_confirmacion();
            continue;
        }
        gps_previamente_ok = true;

        switch (estado_velocidad) {
            case VELOCIDAD_NORMAL:
                if (vel > umbral_velocidad) {
                    if (condicion_confirmada(CONFIRMACION_EXCESO, TIEMPO_CONFIRMAR_ENTRADA_MS)) {
                        estado_velocidad = VELOCIDAD_EXCESO;
                        reset_confirmacion();
                        reset_patrones_alarma();

                        contador_eventos++;
                        ESP_LOGI(TAG, "Evento #%u confirmado (vel=%.2f)", contador_eventos, vel);
                        guardar_contador_eventos(contador_eventos);
                        display_set_number(contador_eventos);

                        buzzer_on();
                        vTaskDelay(pdMS_TO_TICKS(150));
                        buzzer_off();
                    }
                } else if (vel >= umbral_prealerta_entrada()) {
                    if (condicion_confirmada(CONFIRMACION_PREALERTA, TIEMPO_CONFIRMAR_ENTRADA_MS)) {
                        estado_velocidad = VELOCIDAD_PRECAUCION;
                        reset_confirmacion();
                        reset_patrones_alarma();
                        ESP_LOGI(TAG, "PRECAUCION: velocidad cercana al limite (%.2f km/h)", vel);
                    }
                } else {
                    reset_confirmacion();
                }
                break;

            case VELOCIDAD_PRECAUCION:
                if (vel > umbral_velocidad) {
                    if (condicion_confirmada(CONFIRMACION_EXCESO, TIEMPO_CONFIRMAR_ENTRADA_MS)) {
                        estado_velocidad = VELOCIDAD_EXCESO;
                        reset_confirmacion();
                        reset_patrones_alarma();

                        contador_eventos++;
                        ESP_LOGI(TAG, "Evento #%u confirmado (vel=%.2f)", contador_eventos, vel);
                        guardar_contador_eventos(contador_eventos);
                        display_set_number(contador_eventos);

                        buzzer_on();
                        vTaskDelay(pdMS_TO_TICKS(150));
                        buzzer_off();
                    }
                } else if (vel < umbral_prealerta_salida()) {
                    if (condicion_confirmada(CONFIRMACION_NORMAL, TIEMPO_CONFIRMAR_SALIDA_MS)) {
                        estado_velocidad = VELOCIDAD_NORMAL;
                        reset_confirmacion();
                        reset_patrones_alarma();
                        buzzer_off();
                        ESP_LOGI(TAG, "Velocidad nuevamente en zona normal (%.2f km/h)", vel);
                    }
                } else {
                    reset_confirmacion();
                }

                if (estado_velocidad == VELOCIDAD_PRECAUCION) {
                    alerta_precaucion();
                }
                break;

            case VELOCIDAD_EXCESO:
                if (vel < umbral_exceso_salida()) {
                    if (condicion_confirmada(CONFIRMACION_SALIDA_EXCESO, TIEMPO_CONFIRMAR_SALIDA_MS)) {
                        estado_velocidad = vel < umbral_prealerta_salida()
                            ? VELOCIDAD_NORMAL
                            : VELOCIDAD_PRECAUCION;
                        reset_confirmacion();
                        reset_patrones_alarma();
                        buzzer_off();
                        ESP_LOGI(TAG, "Fin del exceso; velocidad %.2f km/h", vel);
                    }
                } else {
                    reset_confirmacion();
                }

                if (estado_velocidad == VELOCIDAD_EXCESO) {
                    alerta_bi_bi();
                }
                break;
        }

        vTaskDelay(pdMS_TO_TICKS(40));
    }
}


