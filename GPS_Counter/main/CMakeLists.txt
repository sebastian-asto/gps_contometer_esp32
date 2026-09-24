idf_component_register(SRCS 
"main.c"
"drivers/led_driver.c"
"drivers/buzzer_driver.c"
"screens/display_7seg.c"
"modules/gps_l80r.c"
"modules/monitor_velocidad.c"
"modules/serial_command.c"
"modules/ble_contometer.c"
               
INCLUDE_DIRS "."
REQUIRES bt nvs_flash esp_driver_uart esp_driver_gpio)
