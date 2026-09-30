#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <newdev.h>

#include <iostream>
#include <string>

#pragma comment(lib, "Newdev.lib")

namespace {
constexpr wchar_t kInstallMarker[] = L"ARVECTUM_DRIVER_PACKAGE_INSTALL_PASS";
constexpr wchar_t kUninstallMarker[] = L"ARVECTUM_DRIVER_PACKAGE_UNINSTALL_PASS";

int Fail(const wchar_t* operation, DWORD error) {
    std::wcerr << L"ARVECTUM_DRIVER_PACKAGE_ERROR operation="
               << operation << L" win32=" << error << std::endl;
    return error == ERROR_SUCCESS ? ERROR_GEN_FAILURE : static_cast<int>(error);
}

bool AbsoluteExistingInf(const wchar_t* input, std::wstring* output) {
    if (input == nullptr || output == nullptr || *input == L'\0') {
        return false;
    }
    wchar_t full[MAX_PATH]{};
    const DWORD length = GetFullPathNameW(input, MAX_PATH, full, nullptr);
    if (length == 0 || length >= MAX_PATH) {
        return false;
    }
    const DWORD attrs = GetFileAttributesW(full);
    if (attrs == INVALID_FILE_ATTRIBUTES ||
        (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        return false;
    }
    std::wstring path(full);
    if (path.size() < 4 ||
        _wcsicmp(path.c_str() + path.size() - 4, L".inf") != 0) {
        return false;
    }
    *output = std::move(path);
    return true;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 3) {
        std::wcerr
            << L"usage: ArvectumDriverPackageTool.exe install|uninstall <absolute-inf-path>"
            << std::endl;
        return ERROR_INVALID_PARAMETER;
    }

    std::wstring inf;
    if (!AbsoluteExistingInf(argv[2], &inf)) {
        return Fail(L"validate_inf", ERROR_FILE_NOT_FOUND);
    }

    BOOL reboot = FALSE;
    if (_wcsicmp(argv[1], L"install") == 0) {
        if (!DiInstallDriverW(nullptr, inf.c_str(), 0, &reboot)) {
            return Fail(L"install", GetLastError());
        }
        std::wcout << kInstallMarker << L" reboot="
                   << (reboot ? L"1" : L"0") << std::endl;
        return reboot ? ERROR_SUCCESS_REBOOT_REQUIRED : ERROR_SUCCESS;
    }

    if (_wcsicmp(argv[1], L"uninstall") == 0) {
        if (!DiUninstallDriverW(nullptr, inf.c_str(), 0, &reboot)) {
            return Fail(L"uninstall", GetLastError());
        }
        std::wcout << kUninstallMarker << L" reboot="
                   << (reboot ? L"1" : L"0") << std::endl;
        return reboot ? ERROR_SUCCESS_REBOOT_REQUIRED : ERROR_SUCCESS;
    }

    return Fail(L"command", ERROR_INVALID_PARAMETER);
}
