#include "Z2Transport.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <poll.h>

struct Z2Connection {
    int fd;
    struct termios original;
    IOUSBDeviceInterface **device;
    IOUSBInterfaceInterface300 **interface;
    UInt8 input, output;
    UInt16 packet_size;
};
static void fail(char *error, size_t capacity, const char *operation, int code) {
    snprintf(error, capacity, "%s (0x%08x)", operation, (unsigned)code);
}
static int number(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    int result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberIntType, &result);
    if (value) CFRelease(value);
    return result;
}
static io_iterator_t candidates(void) {
    io_iterator_t iterator = 0;
    IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBDevice"), &iterator);
    return iterator;
}
static int supported(io_service_t service) {
    return number(service, CFSTR("idVendor")) == 0x0403 && number(service, CFSTR("idProduct")) == 0x1234;
}
int z2_devices(Z2Device *devices, int capacity) {
    io_iterator_t iterator = candidates();
    io_service_t service;
    int count = 0;
    while ((service = IOIteratorNext(iterator))) {
        if (supported(service) && count < capacity) {
            devices[count].location = (uint32_t)number(service, CFSTR("locationID"));
            snprintf(devices[count].name, sizeof(devices[count].name), "Z-2 USB · %08X", devices[count].location);
            count++;
        }
        IOObjectRelease(service);
    }
    if (iterator) IOObjectRelease(iterator);
    return count;
}
void z2_close(Z2Connection *c) {
    if (!c) return;
    if (c->interface) {
        (*c->interface)->USBInterfaceClose(c->interface);
        (*c->interface)->Release(c->interface);
    }
    if (c->device) {
        (*c->device)->USBDeviceClose(c->device);
        (*c->device)->Release(c->device);
    }
    if (c->fd >= 0) { tcsetattr(c->fd, TCSANOW, &c->original); close(c->fd); }
    free(c);
}
static IOReturn control(Z2Connection *c, UInt8 request, UInt16 value, UInt16 index) {
    IOUSBDevRequest req = { .bmRequestType = 0x40, .bRequest = request, .wValue = value, .wIndex = index };
    return (*c->device)->DeviceRequest(c->device, &req);
}
Z2Connection *z2_open_usb(uint32_t location, char *error, size_t capacity) {
    Z2Connection *c = calloc(1, sizeof(*c));
    if (!c) { fail(error, capacity, "Out of memory", ENOMEM); return NULL; }
    c->fd = -1;
    io_iterator_t iterator = candidates();
    io_service_t service;
    IOReturn status = kIOReturnNotFound;
    while ((service = IOIteratorNext(iterator))) {
        if (supported(service) && (uint32_t)number(service, CFSTR("locationID")) == location) {
            IOCFPlugInInterface **plugin = NULL;
            SInt32 score = 0;
            status = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
            if (status == kIOReturnSuccess && plugin) {
                HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&c->device);
                IODestroyPlugInInterface(plugin);
                if (hr || !c->device) status = kIOReturnUnsupported;
            }
            IOObjectRelease(service);
            break;
        }
        IOObjectRelease(service);
    }
    if (iterator) IOObjectRelease(iterator);
    if (status != kIOReturnSuccess || !c->device) goto failed;
    // Never seize a device, detach a system driver, or alter EEPROM/firmware.
    status = (*c->device)->USBDeviceOpen(c->device);
    if (status != kIOReturnSuccess) goto failed;
    UInt8 configuration = 0;
    status = (*c->device)->GetConfiguration(c->device, &configuration);
    if (status != kIOReturnSuccess) goto failed;
    if (!configuration) {
        IOUSBConfigurationDescriptorPtr descriptor;
        status = (*c->device)->GetConfigurationDescriptorPtr(c->device, 0, &descriptor);
        if (status != kIOReturnSuccess) goto failed;
        status = (*c->device)->SetConfiguration(c->device, descriptor->bConfigurationValue);
        if (status != kIOReturnSuccess) goto failed;
    }
    IOUSBFindInterfaceRequest request = { kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare };
    io_iterator_t interfaces = 0;
    status = (*c->device)->CreateInterfaceIterator(c->device, &request, &interfaces);
    if (status != kIOReturnSuccess) goto failed;
    service = IOIteratorNext(interfaces);
    IOObjectRelease(interfaces);
    if (!service) { status = kIOReturnNotFound; goto failed; }
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score;
    status = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (status != kIOReturnSuccess || !plugin) goto failed;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&c->interface);
    IODestroyPlugInInterface(plugin);
    if (hr || !c->interface) { status = kIOReturnUnsupported; goto failed; }
    status = (*c->interface)->USBInterfaceOpen(c->interface);
    if (status != kIOReturnSuccess) goto failed;
    UInt8 endpoints;
    status = (*c->interface)->GetNumEndpoints(c->interface, &endpoints);
    if (status != kIOReturnSuccess) goto failed;
    for (UInt8 pipe = 1; pipe <= endpoints; pipe++) {
        UInt8 direction, number_, transfer, interval;
        UInt16 size;
        status = (*c->interface)->GetPipeProperties(c->interface, pipe, &direction, &number_, &transfer, &size, &interval);
        if (status != kIOReturnSuccess) goto failed;
        if (transfer == kUSBBulk && direction == kUSBIn) { c->input = pipe; c->packet_size = size; }
        if (transfer == kUSBBulk && direction == kUSBOut) c->output = pipe;
    }
    if (!c->input || !c->output || c->packet_size < 3 || c->packet_size > 512) { status = kIOReturnUnsupported; goto failed; }
    // FT232 3 MHz / 312.5 = 9600 baud; half-divisor encoding is bit 14.
    status = control(c, 3, 0x4138, 0);
    if (status == kIOReturnSuccess) status = control(c, 4, 8, 1); // 8N1
    if (status == kIOReturnSuccess) status = control(c, 2, 0, 1); // no flow control
    if (status == kIOReturnSuccess) status = control(c, 9, 2, 1); // 2 ms latency
    if (status != kIOReturnSuccess) goto failed;
    return c;
failed:
    fail(error, capacity, "Cannot open Z-2 USB. Close other reader apps, or select its serial port if available", status);
    z2_close(c);
    return NULL;
}
Z2Connection *z2_open_serial(const char *path, char *error, size_t capacity) {
    Z2Connection *c = calloc(1, sizeof(*c));
    if (!c) { fail(error, capacity, "Out of memory", ENOMEM); return NULL; }
    c->fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (c->fd < 0) { fail(error, capacity, "Cannot open serial port", errno); free(c); return NULL; }
    if (tcgetattr(c->fd, &c->original) < 0) { fail(error, capacity, "Cannot read serial settings", errno); close(c->fd); free(c); return NULL; }
    struct termios settings = c->original;
    cfmakeraw(&settings);
    cfsetspeed(&settings, B9600);
    settings.c_cflag &= ~(PARENB | CSTOPB | CSIZE | CCTS_OFLOW | CRTS_IFLOW);
    settings.c_cflag |= CS8 | CLOCAL | CREAD;
    settings.c_cc[VMIN] = 0; settings.c_cc[VTIME] = 0;
    if (ioctl(c->fd, TIOCEXCL) < 0 || tcsetattr(c->fd, TCSANOW, &settings) < 0) {
        fail(error, capacity, "Cannot configure serial port", errno); z2_close(c); return NULL;
    }
    return c;
}
int z2_decode_ftdi(uint8_t *bytes, int length, int packet_size) {
    if (packet_size < 3 || length < 0) return -1;
    int output = 0;
    for (int offset = 0; offset < length; offset += packet_size) {
        int size = length - offset < packet_size ? length - offset : packet_size;
        if (size < 2 || (bytes[offset + 1] & 0x1e)) return -1; // overrun/parity/framing/break
        memmove(bytes + output, bytes + offset + 2, size - 2);
        output += size - 2;
    }
    return output;
}
int z2_read(Z2Connection *c, uint8_t *bytes, int capacity, char *error, size_t error_capacity) {
    if (c->fd >= 0) {
        struct pollfd p = { c->fd, POLLIN, 0 };
        int ready = poll(&p, 1, 200);
        if (ready < 0 && errno == EINTR) return 0;
        if (ready == 0) return 0;
        if (ready < 0 || (p.revents & (POLLERR | POLLHUP | POLLNVAL))) { fail(error, error_capacity, "Reader disconnected", errno); return -1; }
        int n = (int)read(c->fd, bytes, capacity);
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) return 0;
        if (n < 0) fail(error, error_capacity, "Serial read failed", errno);
        return n;
    }
    uint8_t packet[512];
    UInt32 length = c->packet_size; // one USB packet: each starts with two FTDI status bytes
    IOReturn status = (*c->interface)->ReadPipeTO(c->interface, c->input, packet, &length, 200, 250);
    if (status == kIOUSBTransactionTimeout) return 0;
    if (status != kIOReturnSuccess) { fail(error, error_capacity, "USB read failed", status); return -1; }
    int n = z2_decode_ftdi(packet, (int)length, c->packet_size);
    if (n < 0 || n > capacity) { fail(error, error_capacity, "Invalid USB packet or UART error", EIO); return -1; }
    memcpy(bytes, packet, n);
    return n;
}
int z2_identify(Z2Connection *c, char *error, size_t capacity) {
    uint8_t command = 'I'; // documented, read-only reader identification command
    if (c->fd >= 0) {
        if (write(c->fd, &command, 1) == 1) return 0;
        fail(error, capacity, "Identification request failed", errno); return -1;
    }
    IOReturn status = (*c->interface)->WritePipeTO(c->interface, c->output, &command, 1, 200, 250);
    if (status != kIOReturnSuccess) { fail(error, capacity, "Identification request failed", status); return -1; }
    return 0;
}
