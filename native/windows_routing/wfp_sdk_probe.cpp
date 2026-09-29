#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>

#include <iostream>
#include "wfp_resources.h"

#pragma comment(lib, "Fwpuclnt.lib")

int wmain(int argc, wchar_t** argv) {
    HANDLE engine = nullptr;
    DWORD status = arvectum::routing::OpenWfpEngine(&engine);
    if (status != ERROR_SUCCESS) {
        std::wcerr << L"FwpmEngineOpen0 failed: " << status << std::endl;
        return 2;
    }

    const wchar_t* executable = argc > 0 ? argv[0] : L"";
    FWP_BYTE_BLOB* app_id = nullptr;
    status = FwpmGetAppIdFromFileName0(executable, &app_id);
    if (status != ERROR_SUCCESS || app_id == nullptr || app_id->size == 0) {
        std::wcerr << L"FwpmGetAppIdFromFileName0 failed: " << status << std::endl;
        if (app_id != nullptr) {
            FwpmFreeMemory0(reinterpret_cast<void**>(&app_id));
        }
        FwpmEngineClose0(engine);
        return 3;
    }

    std::wcout << L"WFP SDK probe OK; app-id bytes="
               << app_id->size << std::endl;

    FwpmFreeMemory0(reinterpret_cast<void**>(&app_id));
    FwpmEngineClose0(engine);
    return 0;
}
