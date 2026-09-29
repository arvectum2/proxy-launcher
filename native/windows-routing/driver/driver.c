#pragma warning(push)
#pragma warning(disable: 4201)
#pragma warning(disable: 4324)
#include <ntifs.h>
#include <ntddk.h>
#include <ndis.h>
#include <fwpmk.h>
#include <fwpsk.h>
#include <netioddk.h>
#pragma warning(pop)
#include <initguid.h>
#include "../include/arvectum_routing_guids.h"

#define ARVECTUM_DRIVER_TAG 'RpvA'
#define ARVECTUM_LOOPBACK_V4_NETWORK_ORDER 0x0100007FUL

static PDEVICE_OBJECT g_device = NULL;
static UINT32 g_callout_id = 0;
static HANDLE g_redirect_handle = NULL;

static NTSTATUS NTAPI ArvectumNotify(
    FWPS_CALLOUT_NOTIFY_TYPE notifyType,
    const GUID* filterKey,
    const FWPS_FILTER0* filter)
{
    UNREFERENCED_PARAMETER(notifyType);
    UNREFERENCED_PARAMETER(filterKey);
    UNREFERENCED_PARAMETER(filter);
    return STATUS_SUCCESS;
}

static VOID NTAPI ArvectumClassify(
    const FWPS_INCOMING_VALUES0* inFixedValues,
    const FWPS_INCOMING_METADATA_VALUES0* inMetaValues,
    VOID* layerData,
    const VOID* classifyContext,
    const FWPS_FILTER0* filter,
    UINT64 flowContext,
    FWPS_CLASSIFY_OUT0* classifyOut)
{
    HANDLE classifyHandle = NULL;
    VOID* writableLayerData = NULL;
    FWPS_CONNECT_REQUEST0* request = NULL;
    SOCKADDR_IN* remote = NULL;
    UINT16 redirectPort = 0;
    NTSTATUS status;

    UNREFERENCED_PARAMETER(inFixedValues);
    UNREFERENCED_PARAMETER(layerData);
    UNREFERENCED_PARAMETER(flowContext);

    if (classifyOut == NULL || filter == NULL ||
        (classifyOut->rights & FWPS_RIGHT_ACTION_WRITE) == 0) {
        return;
    }

    classifyOut->actionType = FWP_ACTION_PERMIT;

    /* The user-mode service stores only a validated TCP loopback target port in rawContext. */
    redirectPort = (UINT16)(filter->context & 0xFFFFu);
    if (redirectPort == 0 || classifyContext == NULL || g_redirect_handle == NULL) {
        return;
    }

    if (inMetaValues != NULL &&
        FWPS_IS_METADATA_FIELD_PRESENT(inMetaValues, FWPS_METADATA_FIELD_REDIRECT_RECORD_HANDLE)) {
        FWPS_CONNECTION_REDIRECT_STATE redirectState =
            FwpsQueryConnectionRedirectState0(
                inMetaValues->redirectRecords,
                g_redirect_handle,
                NULL);
        if (redirectState == FWPS_CONNECTION_REDIRECTED_BY_SELF ||
            redirectState == FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF) {
            return;
        }
    }

    status = FwpsAcquireClassifyHandle0((VOID*)classifyContext, 0, &classifyHandle);
    if (!NT_SUCCESS(status)) {
        return;
    }

    status = FwpsAcquireWritableLayerDataPointer0(
        classifyHandle,
        filter->filterId,
        0,
        &writableLayerData,
        classifyOut);
    if (!NT_SUCCESS(status) || writableLayerData == NULL) {
        FwpsReleaseClassifyHandle0(classifyHandle);
        return;
    }

    request = (FWPS_CONNECT_REQUEST0*)writableLayerData;
    remote = (SOCKADDR_IN*)&request->remoteAddressAndPort;
    remote->sin_family = AF_INET;
    remote->sin_port = RtlUshortByteSwap(redirectPort);
    remote->sin_addr.S_un.S_addr = ARVECTUM_LOOPBACK_V4_NETWORK_ORDER;
    request->localRedirectHandle = g_redirect_handle;

    status = FwpsApplyModifiedLayerData0(
        classifyHandle,
        writableLayerData,
        FWPS_CLASSIFY_FLAG_REAUTHORIZE_IF_MODIFIED_BY_OTHERS);

    if (NT_SUCCESS(status)) {
        classifyOut->actionType = FWP_ACTION_PERMIT;
        classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
    }

    FwpsReleaseClassifyHandle0(classifyHandle);
}

static VOID ArvectumUnload(PDRIVER_OBJECT driverObject)
{
    UNREFERENCED_PARAMETER(driverObject);

    if (g_callout_id != 0) {
        FwpsCalloutUnregisterById0(g_callout_id);
        g_callout_id = 0;
    }
    if (g_redirect_handle != NULL) {
        FwpsRedirectHandleDestroy0(g_redirect_handle);
        g_redirect_handle = NULL;
    }
    if (g_device != NULL) {
        IoDeleteDevice(g_device);
        g_device = NULL;
    }
}

NTSTATUS DriverEntry(PDRIVER_OBJECT driverObject, PUNICODE_STRING registryPath)
{
    UNICODE_STRING deviceName = RTL_CONSTANT_STRING(L"\\Device\\ArvectumProxyRouting");
    FWPS_CALLOUT0 callout = {0};
    NTSTATUS status;

    UNREFERENCED_PARAMETER(registryPath);

    driverObject->DriverUnload = ArvectumUnload;

    status = IoCreateDevice(
        driverObject,
        0,
        &deviceName,
        FILE_DEVICE_NETWORK,
        0,
        FALSE,
        &g_device);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = FwpsRedirectHandleCreate0(
        &ARVECTUM_ROUTING_PROVIDER,
        0,
        &g_redirect_handle);
    if (!NT_SUCCESS(status)) {
        ArvectumUnload(driverObject);
        return status;
    }

    callout.calloutKey = ARVECTUM_CONNECT_REDIRECT_V4_CALLOUT;
    callout.classifyFn = ArvectumClassify;
    callout.notifyFn = ArvectumNotify;
    callout.flowDeleteFn = NULL;

    status = FwpsCalloutRegister0(g_device, &callout, &g_callout_id);
    if (!NT_SUCCESS(status)) {
        ArvectumUnload(driverObject);
        return status;
    }

    return STATUS_SUCCESS;
}
