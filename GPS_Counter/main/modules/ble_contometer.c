#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "nvs.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "modules/ble_contometer.h"
#include "modules/gps_l80r.h"
#include "modules/monitor_velocidad.h"

#define BLE_DEVICE_NAME_MAX 24
#define BLE_STATUS_VERSION 1
#define BLE_COMMAND_RESET 0x01
#define BLE_COMMAND_TEST_DISPLAY 0x02

static const char *TAG = "BLE_CONTOMETRO";
static uint8_t own_addr_type;
static uint16_t status_value_handle;
static char device_name[BLE_DEVICE_NAME_MAX + 1];

void ble_store_config_init(void);

// Los UUID de NimBLE se declaran en orden little-endian.
static const ble_uuid128_t service_uuid = BLE_UUID128_INIT(
    0x01, 0x00, 0xA1, 0xC2, 0x49, 0x3F, 0x55, 0xAE,
    0x9D, 0x4C, 0x2B, 0x7A, 0x00, 0x40, 0x1E, 0x7B
);
static const ble_uuid128_t status_uuid = BLE_UUID128_INIT(
    0x02, 0x00, 0xA1, 0xC2, 0x49, 0x3F, 0x55, 0xAE,
    0x9D, 0x4C, 0x2B, 0x7A, 0x00, 0x40, 0x1E, 0x7B
);
static const ble_uuid128_t command_uuid = BLE_UUID128_INIT(
    0x03, 0x00, 0xA1, 0xC2, 0x49, 0x3F, 0x55, 0xAE,
    0x9D, 0x4C, 0x2B, 0x7A, 0x00, 0x40, 0x1E, 0x7B
);
static const ble_uuid128_t name_uuid = BLE_UUID128_INIT(
    0x04, 0x00, 0xA1, 0xC2, 0x49, 0x3F, 0x55, 0xAE,
    0x9D, 0x4C, 0x2B, 0x7A, 0x00, 0x40, 0x1E, 0x7B
);

static void load_device_name(void)
{
    nvs_handle_t handle;
    size_t length = sizeof(device_name);

    if (nvs_open("ble_cfg", NVS_READONLY, &handle) == ESP_OK) {
        if (nvs_get_str(handle, "nombre", device_name, &length) == ESP_OK) {
            nvs_close(handle);
            return;
        }
        nvs_close(handle);
    }

    uint8_t mac[6];
    ESP_ERROR_CHECK(esp_read_mac(mac, ESP_MAC_BT));
    snprintf(device_name, sizeof(device_name), "CONTOMETRO-%02X%02X", mac[4], mac[5]);
}

static esp_err_t save_device_name(const char *name)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open("ble_cfg", NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        return err;
    }

    err = nvs_set_str(handle, "nombre", name);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err;
}

static uint16_t scaled_u16(double value)
{
    if (value <= 0.0) return 0;
    if (value >= 6553.5) return UINT16_MAX;
    return (uint16_t)(value * 10.0 + 0.5);
}

static size_t build_status(uint8_t output[10])
{
    uint16_t counter = monitor_velocidad_get_contador_eventos();
    uint16_t speed = scaled_u16(gps_get_speed_kmh());
    uint16_t limit = scaled_u16(monitor_velocidad_get_umbral());
    bool gps_ok = gps_is_valid() && gps_data_is_fresh(1500);

    output[0] = BLE_STATUS_VERSION;
    output[1] = counter & 0xFF;
    output[2] = counter >> 8;
    output[3] = speed & 0xFF;
    output[4] = speed >> 8;
    output[5] = limit & 0xFF;
    output[6] = limit >> 8;
    output[7] = gps_ok ? 0x01 : 0x00;
    output[8] = (uint8_t)gps_get_satellites();
    output[9] = (uint8_t)monitor_velocidad_get_estado();
    return 10;
}

static int access_status(uint16_t conn_handle, uint16_t attr_handle,
                         struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    uint8_t status[10];
    size_t length = build_status(status);
    int rc = os_mbuf_append(ctxt->om, status, length);
    return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int access_command(uint16_t conn_handle, uint16_t attr_handle,
                          struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    uint8_t command[3] = {0};
    uint16_t length = 0;
    int rc = ble_hs_mbuf_to_flat(ctxt->om, command, sizeof(command), &length);
    if (rc != 0 || length < 1) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    switch (command[0]) {
        case BLE_COMMAND_RESET:
            if (length != 1 || !monitor_velocidad_solicitar_reset()) {
                return BLE_ATT_ERR_UNLIKELY;
            }
            ESP_LOGW(TAG, "Reinicio del contador solicitado por BLE");
            return 0;

        case BLE_COMMAND_TEST_DISPLAY:
            if (length != 3) {
                return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            }
            uint16_t value = (uint16_t)command[1] | ((uint16_t)command[2] << 8);
            if (value > 999 || !monitor_velocidad_solicitar_prueba_display(value)) {
                return BLE_ATT_ERR_UNLIKELY;
            }
            ESP_LOGI(TAG, "Prueba de display solicitada por BLE: %u", value);
            return 0;

        default:
            return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
    }
}

static int access_name(uint16_t conn_handle, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        int rc = os_mbuf_append(ctxt->om, device_name, strlen(device_name));
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    char new_name[BLE_DEVICE_NAME_MAX + 1] = {0};
    uint16_t length = 0;
    int rc = ble_hs_mbuf_to_flat(
        ctxt->om, new_name, BLE_DEVICE_NAME_MAX, &length
    );
    if (rc != 0 || length == 0 || length > BLE_DEVICE_NAME_MAX) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    new_name[length] = '\0';

    if (save_device_name(new_name) != ESP_OK) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    strlcpy(device_name, new_name, sizeof(device_name));
    ble_svc_gap_device_name_set(device_name);
    ESP_LOGI(TAG, "Nombre BLE actualizado: %s", device_name);
    return 0;
}

static const struct ble_gatt_svc_def services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &service_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &status_uuid.u,
                .access_cb = access_status,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &status_value_handle,
            },
            {
                .uuid = &command_uuid.u,
                .access_cb = access_command,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                .uuid = &name_uuid.u,
                .access_cb = access_name,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE,
            },
            {0},
        },
    },
    {0},
};

static void start_advertising(void);

static int gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            if (event->connect.status == 0) {
                ESP_LOGI(TAG, "Aplicacion conectada; handle=%u",
                         event->connect.conn_handle);
            } else {
                start_advertising();
            }
            return 0;

        case BLE_GAP_EVENT_DISCONNECT:
            ESP_LOGI(TAG, "Aplicacion desconectada; motivo=%d",
                     event->disconnect.reason);
            start_advertising();
            return 0;

        case BLE_GAP_EVENT_ADV_COMPLETE:
            start_advertising();
            return 0;

        case BLE_GAP_EVENT_SUBSCRIBE:
            ESP_LOGI(TAG, "Suscripcion estado: notify=%d",
                     event->subscribe.cur_notify);
            return 0;

        default:
            return 0;
    }
}

static void start_advertising(void)
{
    struct ble_hs_adv_fields fields = {0};
    struct ble_hs_adv_fields response = {0};
    struct ble_gap_adv_params params = {0};

    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = (ble_uuid128_t[]) { service_uuid };
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "No se pudo configurar advertising: %d", rc);
        return;
    }

    response.name = (uint8_t *)device_name;
    response.name_len = strlen(device_name);
    response.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&response);
    if (rc != 0) {
        ESP_LOGE(TAG, "No se pudo configurar scan response: %d", rc);
        return;
    }

    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(
        own_addr_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL
    );
    if (rc != 0) {
        ESP_LOGE(TAG, "No se pudo iniciar advertising: %d", rc);
    } else {
        ESP_LOGI(TAG, "BLE visible como %s", device_name);
    }
}

static void on_reset(int reason)
{
    ESP_LOGE(TAG, "NimBLE reiniciado; motivo=%d", reason);
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    assert(rc == 0);
    rc = ble_hs_id_infer_auto(0, &own_addr_type);
    assert(rc == 0);
    start_advertising();
}

static void host_task(void *param)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static void notify_task(void *param)
{
    while (true) {
        if (status_value_handle != 0) {
            ble_gatts_chr_updated(status_value_handle);
        }
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

esp_err_t ble_contometer_init(void)
{
    load_device_name();

    esp_err_t err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "No se pudo iniciar NimBLE: %s", esp_err_to_name(err));
        return err;
    }

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;

    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_svc_gap_device_name_set(device_name);

    int rc = ble_gatts_count_cfg(services);
    if (rc == 0) {
        rc = ble_gatts_add_svcs(services);
    }
    if (rc != 0) {
        ESP_LOGE(TAG, "No se pudo registrar GATT: %d", rc);
        return ESP_FAIL;
    }

    ble_store_config_init();
    nimble_port_freertos_init(host_task);

    if (xTaskCreate(notify_task, "ble_status", 3072, NULL, 2, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }

    return ESP_OK;
}
