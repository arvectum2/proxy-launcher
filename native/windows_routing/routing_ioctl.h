#pragma once

#ifdef _KERNEL_MODE
#include <ntddk.h>
#include <ws2def.h>
#else
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <winioctl.h>
#endif

#define ARVECTUM_ROUTING_IOCTL_VERSION 1u
#define ARVECTUM_ROUTING_CONTEXT_MAGIC 0x52565041u

#define IOCTL_ARVECTUM_ROUTING_SET_CONFIG \
    CTL_CODE(FILE_DEVICE_NETWORK, 0x801, METHOD_BUFFERED, FILE_WRITE_DATA)

typedef struct _ARVECTUM_ROUTING_CONFIG {
    ULONG version;
    ULONG enabled;
    ULONG proxy_pid;
    ULONG proxy_port;
} ARVECTUM_ROUTING_CONFIG;
typedef struct _ARVECTUM_REDIRECT_CONTEXT {
    ULONG magic;
    ULONG version;
    SOCKADDR_STORAGE original_remote;
    SOCKADDR_STORAGE original_local;
} ARVECTUM_REDIRECT_CONTEXT;
