#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct Z2Connection Z2Connection;
typedef struct { uint32_t location; char name[256]; } Z2Device;
int z2_devices(Z2Device *devices, int capacity);
Z2Connection *z2_open_usb(uint32_t location, char *error, size_t capacity);
Z2Connection *z2_open_serial(const char *path, char *error, size_t capacity);
int z2_read(Z2Connection *connection, uint8_t *bytes, int capacity, char *error, size_t error_capacity);
int z2_identify(Z2Connection *connection, char *error, size_t capacity);
void z2_close(Z2Connection *connection);
// In-place decoding. Returns -1 on malformed packets or UART errors.
int z2_decode_ftdi(uint8_t *bytes, int length, int packet_size);
