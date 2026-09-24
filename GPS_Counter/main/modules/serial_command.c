#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "driver/uart.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "modules/monitor_velocidad.h"
#include "modules/serial_command.h"

#define SERIAL_COMMAND_UART          UART_NUM_0
#define SERIAL_COMMAND_RX_BUFFER     256
#define SERIAL_COMMAND_TASK_STACK    3072
#define SERIAL_COMMAND_TASK_PRIORITY 2

#define FRAME_HEADER_1  0xA5
#define FRAME_HEADER_2  0x5A
#define FRAME_SIZE      6
#define COMMAND_RESET   0x01

static const char *TAG = "SERIAL_CMD";

static uint8_t frame_checksum(const uint8_t *frame)
{
    uint8_t checksum = 0;

    // El ultimo byte de la trama contiene el checksum recibido.
    for (size_t i = 0; i < FRAME_SIZE - 1; i++) {
        checksum ^= frame[i];
    }

    return checksum;
}

static void process_frame(const uint8_t *frame)
{
    if (frame_checksum(frame) != frame[FRAME_SIZE - 1]) {
        ESP_LOGW(TAG, "Trama UART0 descartada: checksum incorrecto");
        return;
    }

    const uint8_t command = frame[2];
    const uint16_t value = ((uint16_t)frame[3] << 8) | frame[4];

    if (command != COMMAND_RESET || value != 0) {
        ESP_LOGW(TAG, "Comando UART0 no reconocido: 0x%02X", command);
        return;
    }

    if (monitor_velocidad_solicitar_reset()) {
        ESP_LOGW(TAG, "RESET valido recibido por UART0; reinicio solicitado");
    } else {
        ESP_LOGE(TAG, "No se pudo solicitar el reinicio del contador");
    }
}

static void task_serial_command(void *pvParameters)
{
    uint8_t rx_data[32];
    uint8_t frame[FRAME_SIZE];
    size_t frame_pos = 0;

    ESP_LOGI(TAG, "UART0 lista. Trama RESET: A5 5A 01 00 00 FE");

    while (true) {
        int len = uart_read_bytes(
            SERIAL_COMMAND_UART,
            rx_data,
            sizeof(rx_data),
            pdMS_TO_TICKS(100)
        );

        for (int i = 0; i < len; i++) {
            uint8_t byte = rx_data[i];

            if (frame_pos == 0) {
                if (byte == FRAME_HEADER_1) {
                    frame[frame_pos++] = byte;
                }
                continue;
            }

            if (frame_pos == 1) {
                if (byte == FRAME_HEADER_2) {
                    frame[frame_pos++] = byte;
                } else {
                    // Permite resincronizar si llega A5 nuevamente.
                    frame_pos = (byte == FRAME_HEADER_1) ? 1 : 0;
                    if (frame_pos == 1) {
                        frame[0] = byte;
                    }
                }
                continue;
            }

            frame[frame_pos++] = byte;

            if (frame_pos == FRAME_SIZE) {
                process_frame(frame);
                frame_pos = 0;
            }
        }
    }
}

esp_err_t serial_command_init(void)
{
    if (!uart_is_driver_installed(SERIAL_COMMAND_UART)) {
        esp_err_t err = uart_driver_install(
            SERIAL_COMMAND_UART,
            SERIAL_COMMAND_RX_BUFFER,
            0,
            0,
            NULL,
            0
        );

        if (err != ESP_OK) {
            ESP_LOGE(TAG, "No se pudo instalar el driver UART0: %s", esp_err_to_name(err));
            return err;
        }
    }

    // Descarta bytes residuales recibidos durante el arranque.
    uart_flush_input(SERIAL_COMMAND_UART);

    BaseType_t task_created = xTaskCreate(
        task_serial_command,
        "task_serial_command",
        SERIAL_COMMAND_TASK_STACK,
        NULL,
        SERIAL_COMMAND_TASK_PRIORITY,
        NULL
    );

    if (task_created != pdPASS) {
        ESP_LOGE(TAG, "No se pudo crear la tarea de comandos UART0");
        return ESP_ERR_NO_MEM;
    }

    return ESP_OK;
}
