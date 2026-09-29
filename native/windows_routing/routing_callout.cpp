#define INITGUID
#pragma warning(push)
#pragma warning(disable:4201)
#pragma warning(disable:4324)
extern "C" {
#include <ntifs.h>
#include <ntddk.h>
#include <ndis.h>
#include <fwpmk.h>
#include <fwpsk.h>
#include <netioddk.h>
#include <wdmsec.h>
#include <ws2def.h>
#include <ws2ipdef.h>
}
#pragma warning(pop)

#include "routing_ioctl.h"

#define ARVECTUM_POOL_TAG 'RvPA'

static const GUID kProviderKey =
    {0x7f8764a3, 0x5f75, 0x4c43, {0xa8, 0x82, 0x52, 0x15, 0x53, 0x63, 0xb9, 0x31}};
static const GUID kCalloutV4Key =
    {0x83751a2f, 0x2b83, 0x49cc, {0x8d, 0xc1, 0x50, 0xcf, 0xe1, 0xf5, 0x0b, 0x0b}};
static const GUID kCalloutV6Key =
    {0x6c08d7a8, 0x5afd, 0x4012, {0x9d, 0x17, 0x2d, 0xb3, 0xd1, 0xf0, 0xb1, 0x7d}};
static const GUID kDeviceClassGuid =
    {0x2ab3a5d4, 0x1a73, 0x47b7, {0xa8, 0x9a, 0xe4, 0xf4, 0xb1, 0x5f, 0xc7, 0x20}};

static UNICODE_STRING g_device_name =
    RTL_CONSTANT_STRING(L"\\Device\\ArvectumProxyRouting");
static UNICODE_STRING g_symbolic_link =
    RTL_CONSTANT_STRING(L"\\DosDevices\\ArvectumProxyRouting");

static PDEVICE_OBJECT g_device_object = NULL;
static UINT32 g_callout_v4_id = 0;
static UINT32 g_callout_v6_id = 0;
static HANDLE g_redirect_handle = NULL;
static volatile LONG g_enabled = 0;
static volatile LONG g_proxy_pid = 0;
static volatile LONG g_proxy_port = 0;
static volatile LONG g_diagnostic_sequence = 0;
static ARVECTUM_ROUTING_DIAGNOSTIC_EVENT
    g_diagnostic_events[ARVECTUM_ROUTING_DIAGNOSTIC_EVENT_COUNT]{};

static NTSTATUS CompleteIrp(
    PIRP irp,
    NTSTATUS status,
    ULONG_PTR information)
{
    irp->IoStatus.Status = status;
    irp->IoStatus.Information = information;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}

static NTSTATUS DispatchCreateClose(
    PDEVICE_OBJECT device_object,
    PIRP irp)
{
    UNREFERENCED_PARAMETER(device_object);
    return CompleteIrp(irp, STATUS_SUCCESS, 0);
}

static NTSTATUS DispatchDeviceControl(
    PDEVICE_OBJECT device_object,
    PIRP irp)
{
    PIO_STACK_LOCATION stack;
    ULONG code;

    UNREFERENCED_PARAMETER(device_object);
    stack = IoGetCurrentIrpStackLocation(irp);
    code = stack->Parameters.DeviceIoControl.IoControlCode;

    if (code == IOCTL_ARVECTUM_ROUTING_GET_DIAGNOSTICS) {
        if (stack->Parameters.DeviceIoControl.OutputBufferLength <
            sizeof(ARVECTUM_ROUTING_DIAGNOSTICS)) {
            return CompleteIrp(irp, STATUS_BUFFER_TOO_SMALL, 0);
        }
        ARVECTUM_ROUTING_DIAGNOSTICS* diagnostics =
            (ARVECTUM_ROUTING_DIAGNOSTICS*)irp->AssociatedIrp.SystemBuffer;
        if (diagnostics == NULL) {
            return CompleteIrp(irp, STATUS_INVALID_PARAMETER, 0);
        }
        RtlZeroMemory(diagnostics, sizeof(*diagnostics));
        diagnostics->version = ARVECTUM_ROUTING_DIAGNOSTICS_VERSION;
        diagnostics->count = ARVECTUM_ROUTING_DIAGNOSTIC_EVENT_COUNT;
        RtlCopyMemory(
            diagnostics->events,
            g_diagnostic_events,
            sizeof(g_diagnostic_events));
        return CompleteIrp(
            irp,
            STATUS_SUCCESS,
            sizeof(ARVECTUM_ROUTING_DIAGNOSTICS));
    }

    if (code != IOCTL_ARVECTUM_ROUTING_SET_CONFIG) {
        return CompleteIrp(irp, STATUS_INVALID_DEVICE_REQUEST, 0);
    }
    if (stack->Parameters.DeviceIoControl.InputBufferLength <
        sizeof(ARVECTUM_ROUTING_CONFIG)) {
        return CompleteIrp(irp, STATUS_BUFFER_TOO_SMALL, 0);
    }

    ARVECTUM_ROUTING_CONFIG* config =
        (ARVECTUM_ROUTING_CONFIG*)irp->AssociatedIrp.SystemBuffer;
    if (config == NULL ||
        config->version != ARVECTUM_ROUTING_IOCTL_VERSION ||
        config->proxy_port > 65535u) {
        return CompleteIrp(irp, STATUS_INVALID_PARAMETER, 0);
    }

    if (config->enabled != 0 &&
        (config->proxy_pid == 0 || config->proxy_port == 0)) {
        return CompleteIrp(irp, STATUS_INVALID_PARAMETER, 0);
    }

    if (config->enabled != 0) {
        RtlZeroMemory(g_diagnostic_events, sizeof(g_diagnostic_events));
        InterlockedExchange(&g_diagnostic_sequence, 0);
    }
    InterlockedExchange(&g_proxy_pid, (LONG)config->proxy_pid);
    InterlockedExchange(&g_proxy_port, (LONG)config->proxy_port);
    InterlockedExchange(&g_enabled, config->enabled ? 1 : 0);
    return CompleteIrp(irp, STATUS_SUCCESS, 0);
}

static NTSTATUS NTAPI NotifyFn(
    FWPS_CALLOUT_NOTIFY_TYPE notify_type,
    const GUID* filter_key,
    FWPS_FILTER1* filter)
{
    UNREFERENCED_PARAMETER(notify_type);
    UNREFERENCED_PARAMETER(filter_key);
    UNREFERENCED_PARAMETER(filter);
    return STATUS_SUCCESS;
}
static BOOLEAN ShouldSkipRedirect(
    const FWPS_INCOMING_METADATA_VALUES0* meta)
{
    FWPS_CONNECTION_REDIRECT_STATE state;

    if (meta == NULL || meta->redirectRecords == NULL ||
        g_redirect_handle == NULL) {
        return FALSE;
    }

    state = FwpsQueryConnectionRedirectState0(
        meta->redirectRecords,
        g_redirect_handle,
        NULL);

    if (state == FWPS_CONNECTION_REDIRECTED_BY_SELF ||
        state == FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF) {
        return TRUE;
    }
    return FALSE;
}

static VOID SetLoopbackTarget(
    FWPS_CONNECT_REQUEST0* request,
    UINT16 layer_id,
    USHORT proxy_port)
{
    if (layer_id == FWPS_LAYER_ALE_CONNECT_REDIRECT_V4) {
        SOCKADDR_IN* remote =
            (SOCKADDR_IN*)&request->remoteAddressAndPort;
        remote->sin_family = AF_INET;
        remote->sin_addr.S_un.S_addr =
            RtlUlongByteSwap(0x7f000001u);
        remote->sin_port = RtlUshortByteSwap(proxy_port);
    } else {
        SOCKADDR_IN6* remote =
            (SOCKADDR_IN6*)&request->remoteAddressAndPort;
        RtlZeroMemory(&remote->sin6_addr, sizeof(remote->sin6_addr));
        remote->sin6_family = AF_INET6;
        remote->sin6_addr.u.Byte[15] = 1;
        remote->sin6_port = RtlUshortByteSwap(proxy_port);
    }
}
static BOOLEAN CaptureClassifyEndpoints(
    const FWPS_INCOMING_VALUES0* fixed_values,
    SOCKADDR_STORAGE* remote_storage,
    SOCKADDR_STORAGE* local_storage)
{
    if (fixed_values == NULL ||
        remote_storage == NULL ||
        local_storage == NULL) {
        return FALSE;
    }

    RtlZeroMemory(remote_storage, sizeof(*remote_storage));
    RtlZeroMemory(local_storage, sizeof(*local_storage));

    if (fixed_values->layerId == FWPS_LAYER_ALE_CONNECT_REDIRECT_V4) {
        const FWP_VALUE0* remote_address =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_REMOTE_ADDRESS].value;
        const FWP_VALUE0* remote_port =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_REMOTE_PORT].value;
        const FWP_VALUE0* local_address =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_LOCAL_ADDRESS].value;
        const FWP_VALUE0* local_port =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_LOCAL_PORT].value;
        if (remote_address->type != FWP_UINT32 ||
            remote_port->type != FWP_UINT16 ||
            local_address->type != FWP_UINT32 ||
            local_port->type != FWP_UINT16) {
            return FALSE;
        }
        SOCKADDR_IN* remote = (SOCKADDR_IN*)remote_storage;
        SOCKADDR_IN* local = (SOCKADDR_IN*)local_storage;
        remote->sin_family = AF_INET;
        remote->sin_addr.S_un.S_addr =
            RtlUlongByteSwap(remote_address->uint32);
        remote->sin_port = RtlUshortByteSwap(remote_port->uint16);
        local->sin_family = AF_INET;
        local->sin_addr.S_un.S_addr =
            RtlUlongByteSwap(local_address->uint32);
        local->sin_port = RtlUshortByteSwap(local_port->uint16);
        return TRUE;
    }

    if (fixed_values->layerId == FWPS_LAYER_ALE_CONNECT_REDIRECT_V6) {
        const FWP_VALUE0* remote_address =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_IP_REMOTE_ADDRESS].value;
        const FWP_VALUE0* remote_port =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_IP_REMOTE_PORT].value;
        const FWP_VALUE0* local_address =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_IP_LOCAL_ADDRESS].value;
        const FWP_VALUE0* local_port =
            &fixed_values->incomingValue[
                FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_IP_LOCAL_PORT].value;
        if (remote_address->type != FWP_BYTE_ARRAY16_TYPE ||
            remote_address->byteArray16 == NULL ||
            remote_port->type != FWP_UINT16 ||
            local_address->type != FWP_BYTE_ARRAY16_TYPE ||
            local_address->byteArray16 == NULL ||
            local_port->type != FWP_UINT16) {
            return FALSE;
        }
        SOCKADDR_IN6* remote = (SOCKADDR_IN6*)remote_storage;
        SOCKADDR_IN6* local = (SOCKADDR_IN6*)local_storage;
        remote->sin6_family = AF_INET6;
        RtlCopyMemory(
            &remote->sin6_addr,
            remote_address->byteArray16->byteArray16,
            sizeof(remote->sin6_addr));
        remote->sin6_port = RtlUshortByteSwap(remote_port->uint16);
        local->sin6_family = AF_INET6;
        RtlCopyMemory(
            &local->sin6_addr,
            local_address->byteArray16->byteArray16,
            sizeof(local->sin6_addr));
        local->sin6_port = RtlUshortByteSwap(local_port->uint16);
        return TRUE;
    }

    return FALSE;
}

static ARVECTUM_ROUTING_DIAGNOSTIC_EVENT* BeginDiagnosticEvent(
    const FWPS_INCOMING_VALUES0* fixed_values,
    const FWPS_INCOMING_METADATA_VALUES0* meta)
{
    const LONG sequence = InterlockedIncrement(&g_diagnostic_sequence);
    const ULONG index =
        (ULONG)(sequence - 1) % ARVECTUM_ROUTING_DIAGNOSTIC_EVENT_COUNT;
    ARVECTUM_ROUTING_DIAGNOSTIC_EVENT* event =
        &g_diagnostic_events[index];

    RtlZeroMemory(event, sizeof(*event));
    event->sequence = (ULONG)sequence;
    if (fixed_values != NULL) {
        event->layer_id = fixed_values->layerId;
        if (fixed_values->layerId == FWPS_LAYER_ALE_CONNECT_REDIRECT_V4) {
            const FWP_VALUE0* flags =
                &fixed_values->incomingValue[
                    FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_FLAGS].value;
            if (flags->type == FWP_UINT32) {
                event->condition_flags = flags->uint32;
            }
        } else if (
            fixed_values->layerId == FWPS_LAYER_ALE_CONNECT_REDIRECT_V6) {
            const FWP_VALUE0* flags =
                &fixed_values->incomingValue[
                    FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_FLAGS].value;
            if (flags->type == FWP_UINT32) {
                event->condition_flags = flags->uint32;
            }
        }
        CaptureClassifyEndpoints(
            fixed_values,
            &event->fixed_remote,
            &event->fixed_local);
    }
    if (meta != NULL) {
        if ((meta->currentMetadataValues & FWPS_METADATA_FIELD_PROCESS_ID) != 0) {
            event->process_id = meta->processId;
        }
        if ((meta->currentMetadataValues &
                FWPS_METADATA_FIELD_LOCAL_REDIRECT_TARGET_PID) != 0) {
            event->local_redirect_target_pid =
                meta->localRedirectTargetPID;
        }
        if (meta->redirectRecords != NULL) {
            event->has_redirect_records = 1;
            if (g_redirect_handle != NULL) {
                event->redirect_state = (ULONG)
                    FwpsQueryConnectionRedirectState0(
                        meta->redirectRecords,
                        g_redirect_handle,
                        NULL);
            }
        }
    }
    return event;
}
static VOID NTAPI ClassifyFn(
    const FWPS_INCOMING_VALUES0* fixed_values,
    const FWPS_INCOMING_METADATA_VALUES0* meta,
    VOID* layer_data,
    const VOID* classify_context,
    const FWPS_FILTER1* filter,
    UINT64 flow_context,
    FWPS_CLASSIFY_OUT0* classify_out)
{
    UINT64 classify_handle = 0;
    PVOID writable = NULL;
    FWPS_CONNECT_REQUEST0* request = NULL;
    ARVECTUM_REDIRECT_CONTEXT* redirect_context = NULL;
    ARVECTUM_ROUTING_DIAGNOSTIC_EVENT* diagnostic_event = NULL;
    NTSTATUS status;
    LONG enabled;
    LONG proxy_pid;
    LONG proxy_port;

    UNREFERENCED_PARAMETER(layer_data);
    UNREFERENCED_PARAMETER(flow_context);

    if (classify_out == NULL ||
        (classify_out->rights & FWPS_RIGHT_ACTION_WRITE) == 0) {
        return;
    }

    classify_out->actionType = FWP_ACTION_PERMIT;
    enabled = InterlockedCompareExchange(&g_enabled, 0, 0);
    proxy_pid = InterlockedCompareExchange(&g_proxy_pid, 0, 0);
    proxy_port = InterlockedCompareExchange(&g_proxy_port, 0, 0);

    if (!enabled || proxy_pid <= 0 ||
        proxy_port <= 0 || proxy_port > 65535 ||
        fixed_values == NULL || filter == NULL ||
        classify_context == NULL) {
        return;
    }
    diagnostic_event = BeginDiagnosticEvent(fixed_values, meta);
    if (ShouldSkipRedirect(meta)) {
        return;
    }
    if (meta != NULL &&
        (meta->currentMetadataValues & FWPS_METADATA_FIELD_PROCESS_ID) != 0 &&
        meta->processId == (UINT64)(ULONG)proxy_pid) {
        return;
    }
    if (meta != NULL &&
        (meta->currentMetadataValues &
            FWPS_METADATA_FIELD_LOCAL_REDIRECT_TARGET_PID) != 0 &&
        meta->localRedirectTargetPID == (DWORD)proxy_pid) {
        return;
    }
    status = FwpsAcquireClassifyHandle0(
        (PVOID)classify_context,
        0,
        &classify_handle);
    if (!NT_SUCCESS(status)) {
        classify_out->actionType = FWP_ACTION_BLOCK;
        classify_out->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        return;
    }

    status = FwpsAcquireWritableLayerDataPointer0(
        classify_handle,
        filter->filterId,
        0,
        &writable,
        classify_out);
    if (!NT_SUCCESS(status) || writable == NULL) {
        FwpsReleaseClassifyHandle0(classify_handle);
        classify_out->actionType = FWP_ACTION_BLOCK;
        classify_out->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        return;
    }

    request = (FWPS_CONNECT_REQUEST0*)writable;
    if (diagnostic_event != NULL) {
        RtlCopyMemory(
            &diagnostic_event->writable_remote,
            &request->remoteAddressAndPort,
            sizeof(SOCKADDR_STORAGE));
        RtlCopyMemory(
            &diagnostic_event->writable_local,
            &request->localAddressAndPort,
            sizeof(SOCKADDR_STORAGE));
    }
    if (request->previousVersion != NULL &&
        (request->previousVersion->modifierFilterId == filter->filterId ||
         request->previousVersion->localRedirectHandle != NULL)) {
        classify_out->actionType = FWP_ACTION_PERMIT;
        classify_out->rights |= FWPS_RIGHT_ACTION_WRITE;
        FwpsApplyModifiedLayerData0(classify_handle, writable, 0);
        FwpsReleaseClassifyHandle0(classify_handle);
        return;
    }
#pragma warning(push)
#pragma warning(disable:4996)
    redirect_context = (ARVECTUM_REDIRECT_CONTEXT*)
        ExAllocatePoolWithTag(
            NonPagedPoolNx,
            sizeof(ARVECTUM_REDIRECT_CONTEXT),
            ARVECTUM_POOL_TAG);
#pragma warning(pop)
    if (redirect_context == NULL) {
        classify_out->actionType = FWP_ACTION_BLOCK;
        FwpsApplyModifiedLayerData0(classify_handle, writable, 0);
        FwpsReleaseClassifyHandle0(classify_handle);
        return;
    }
    RtlZeroMemory(
        redirect_context,
        sizeof(ARVECTUM_REDIRECT_CONTEXT));
    redirect_context->magic = ARVECTUM_ROUTING_CONTEXT_MAGIC;
    redirect_context->version = ARVECTUM_ROUTING_CONTEXT_VERSION;
    if (!CaptureClassifyEndpoints(
            fixed_values,
            &redirect_context->original_remote,
            &redirect_context->original_local)) {
        ExFreePoolWithTag(redirect_context, ARVECTUM_POOL_TAG);
        classify_out->actionType = FWP_ACTION_BLOCK;
        FwpsApplyModifiedLayerData0(classify_handle, writable, 0);
        FwpsReleaseClassifyHandle0(classify_handle);
        return;
    }
    if (meta != NULL &&
        (meta->currentMetadataValues &
            FWPS_METADATA_FIELD_ORIGINAL_DESTINATION) != 0 &&
        meta->originalDestination != NULL) {
        RtlCopyMemory(
            &redirect_context->metadata_original,
            meta->originalDestination,
            sizeof(SOCKADDR_STORAGE));
        redirect_context->flags |=
            ARVECTUM_REDIRECT_CONTEXT_HAS_METADATA_ORIGINAL;
    }

    request->localRedirectHandle = g_redirect_handle;
    request->localRedirectTargetPID = (DWORD)proxy_pid;
    request->localRedirectContext = redirect_context;
    request->localRedirectContextSize =
        sizeof(ARVECTUM_REDIRECT_CONTEXT);

    SetLoopbackTarget(
        request,
        fixed_values->layerId,
        (USHORT)proxy_port);

    classify_out->actionType = FWP_ACTION_PERMIT;
    FwpsApplyModifiedLayerData0(classify_handle, writable, 0);
    FwpsReleaseClassifyHandle0(classify_handle);
}
static VOID DriverUnload(PDRIVER_OBJECT driver_object)
{
    UNREFERENCED_PARAMETER(driver_object);

    InterlockedExchange(&g_enabled, 0);
    if (g_callout_v6_id != 0) {
        FwpsCalloutUnregisterById0(g_callout_v6_id);
        g_callout_v6_id = 0;
    }
    if (g_callout_v4_id != 0) {
        FwpsCalloutUnregisterById0(g_callout_v4_id);
        g_callout_v4_id = 0;
    }
    if (g_redirect_handle != NULL) {
        FwpsRedirectHandleDestroy0(g_redirect_handle);
        g_redirect_handle = NULL;
    }

    IoDeleteSymbolicLink(&g_symbolic_link);
    if (g_device_object != NULL) {
        IoDeleteDevice(g_device_object);
        g_device_object = NULL;
    }
}

extern "C" DRIVER_INITIALIZE DriverEntry;

extern "C" NTSTATUS DriverEntry(
    PDRIVER_OBJECT driver_object,
    PUNICODE_STRING registry_path)
{
    NTSTATUS status;
    FWPS_CALLOUT1 callout;

    UNREFERENCED_PARAMETER(registry_path);
    driver_object->DriverUnload = DriverUnload;
    driver_object->MajorFunction[IRP_MJ_CREATE] =
        DispatchCreateClose;
    driver_object->MajorFunction[IRP_MJ_CLOSE] =
        DispatchCreateClose;
    driver_object->MajorFunction[IRP_MJ_DEVICE_CONTROL] =
        DispatchDeviceControl;
    status = IoCreateDeviceSecure(
        driver_object,
        0,
        &g_device_name,
        FILE_DEVICE_NETWORK,
        FILE_DEVICE_SECURE_OPEN,
        FALSE,
        &SDDL_DEVOBJ_SYS_ALL_ADM_ALL,
        &kDeviceClassGuid,
        &g_device_object);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = IoCreateSymbolicLink(
        &g_symbolic_link,
        &g_device_name);
    if (!NT_SUCCESS(status)) {
        DriverUnload(driver_object);
        return status;
    }

    status = FwpsRedirectHandleCreate0(
        &kProviderKey,
        0,
        &g_redirect_handle);
    if (!NT_SUCCESS(status)) {
        DriverUnload(driver_object);
        return status;
    }

    RtlZeroMemory(&callout, sizeof(callout));
    callout.calloutKey = kCalloutV4Key;
    callout.classifyFn = ClassifyFn;
    callout.notifyFn = NotifyFn;
    status = FwpsCalloutRegister1(
        g_device_object,
        &callout,
        &g_callout_v4_id);
    if (!NT_SUCCESS(status)) {
        DriverUnload(driver_object);
        return status;
    }

    RtlZeroMemory(&callout, sizeof(callout));
    callout.calloutKey = kCalloutV6Key;
    callout.classifyFn = ClassifyFn;
    callout.notifyFn = NotifyFn;
    status = FwpsCalloutRegister1(
        g_device_object,
        &callout,
        &g_callout_v6_id);
    if (!NT_SUCCESS(status)) {
        DriverUnload(driver_object);
        return status;
    }

    g_device_object->Flags &= ~DO_DEVICE_INITIALIZING;
    return STATUS_SUCCESS;
}
