#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <array>
#include <cstdlib>
#include <iostream>
#include <string>

#pragma comment(lib, "Ws2_32.lib")

int wmain(int argc, wchar_t** argv) {
    if (argc != 4) {
        std::wcerr << L"usage: ArvectumWfpSelectedClient.exe <ipv4> <port> <host>\n";
        return 2;
    }
    const unsigned long port = std::wcstoul(argv[2], nullptr, 10);
    if (port == 0 || port > 65535) return 3;

    WSADATA winsock{};
    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) return 4;
    SOCKET client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (client == INVALID_SOCKET) { WSACleanup(); return 5; }

    SOCKADDR_IN destination{};
    destination.sin_family = AF_INET;
    destination.sin_port = htons(static_cast<USHORT>(port));
    if (InetPtonW(AF_INET, argv[1], &destination.sin_addr) != 1) {
        closesocket(client); WSACleanup(); return 6;
    }
    if (connect(client, reinterpret_cast<const sockaddr*>(&destination), sizeof(destination)) == SOCKET_ERROR) {
        closesocket(client); WSACleanup(); return 7;
    }

    const int host_bytes = WideCharToMultiByte(CP_UTF8, 0, argv[3], -1, nullptr, 0, nullptr, nullptr);
    if (host_bytes <= 1) { closesocket(client); WSACleanup(); return 8; }
    std::string host(static_cast<size_t>(host_bytes - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, argv[3], -1, host.data(), host_bytes, nullptr, nullptr);

    const std::string request = "GET / HTTP/1.1\r\nHost: " + host +
        "\r\nConnection: close\r\nUser-Agent: Arvectum-WFP-SelectedClient\r\n\r\n";
    size_t sent_total = 0;
    while (sent_total < request.size()) {
        const int sent = send(client, request.data() + sent_total,
            static_cast<int>(request.size() - sent_total), 0);
        if (sent <= 0) { closesocket(client); WSACleanup(); return 9; }
        sent_total += static_cast<size_t>(sent);
    }

    std::array<char, 2048> response{};
    const int received = recv(client, response.data(), static_cast<int>(response.size() - 1), 0);
    closesocket(client);
    WSACleanup();
    if (received <= 0) return 10;

    const std::string prefix(response.data(), static_cast<size_t>(received));
    if (prefix.find(" 200 ") == std::string::npos) return 11;
    std::cout << "ARVECTUM_WFP_SELECTED_CLIENT_HTTP_200\n";
    return 0;
}
