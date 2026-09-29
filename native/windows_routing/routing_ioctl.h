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
#define ARVECTUM_ROUTING_CONTEXT_VERSION 2u
#define ARVECTUM_ROUTING_CONTEXT_MAGIC 0x52565041u
#define ARVECTUM_REDIRECT_CONTEXT_HAS_METADATA_ORIGINAL 0x00000001u
#define ARVECTUM_ROUTING_DIAGNOSTICS_VERSION 1u
#define ARVECTUM_ROUTING_DIAGNOSTIC_EVENT_COUNT 8u

#define IOCTL_ARVECTUM_ROUTING_SET_CONFIG \
    CTL_CODE(FILE_DEVICE_NETWORK, 0x801, METHOD_BUFFERED, FILE_WRITE_DATA)
#define IOCTL_ARVECTUM_ROUTING_GET_DIAGNOSTICS \
    CTL_CODE(FILE_DEVICE_NETWORK, 0x802, METHOD_BUFFERED, FILE_READ_DATA)

typedef struct _ARVECTUM_ROUTING_CONFIG {
    ULONG version;
    ULONG enabled;
    ULONG proxy_pid;
    ULONG proxy_port;
} ARVECTUM_ROUTING_CONFIG;

typedef struct _ARVECTUM_ROUTING_DIAGNOSTIC_EVENT {
    ULONG sequence;
    ULONG layer_id;
    ULONG condition_flags;
    ULONG redirect_state;
    ULONGLONG process_id;
    ULONG local_redirect_target_pid;
    ULONG has_redirect_records;
    ULONG previous_version_present;
    ULONG previous_local_redirect_handle_present;
    ULONGLONG previous_modifier_filter_id;
    SOCKADDR_STORAGE fixed_remote;
    SOCKADDR_STORAGE fixed_local;
    SOCKADDR_STORAGE writable_remote;
    SOCKADDR_STORAGE writable_local;
} ARVECTUM_ROUTING_DIAGNOSTIC_EVENT;

typedef struct _ARVECTUM_ROUTING_DIAGNOSTICS {
    ULONG version;
    ULONG count;
    ARVECTUM_ROUTING_DIAGNOSTIC_EVENT
        events[ARVECTUM_ROUTING_DIAGNOSTIC_EVENT_COUNT];
} ARVECTUM_ROUTING_DIAGNOSTICS;

typedef struct _ARVECTUM_REDIRECT_CONTEXT {
    ULONG magic;
    ULONG version;
    SOCKADDR_STORAGE original_remote;
    SOCKADDR_STORAGE original_local;
    ULONG flags;
    ULONG reserved;
    SOCKADDR_STORAGE metadata_original;
} ARVECTUM_REDIRECT_CONTEXT;
