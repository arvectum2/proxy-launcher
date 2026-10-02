#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <cstdlib>
#include <iostream>
#include <string>

#pragma comment(lib, "Ws2_32.lib")

namespace {

bool ParsePort(const char* text, unsigned short* output) {
    if (text == nullptr || output == nullptr) {
        return false;
    }
    char* end = nullptr;
    const unsigned long value = std::strtoul(text, &end, 10);
    if (end == text || *end != '\0' || value == 0 || value > 65535) {
        return false;
    }
    *output = static_cast<unsigned short>(value);
    return true;
}

int ParseFamily(const char* text) {
    if (text == nullptr || std::string(text) == "ipv4") {
        return AF_INET;
    }
    if (std::string(text) == "ipv6") {
        return AF_INET6;
    }
    return AF_UNSPEC;
}

SOCKET ConnectLoopback(unsigned short port, int family) {
    SOCKET socket_handle = socket(family, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET) {
        return INVALID_SOCKET;
    }
    int result = SOCKET_ERROR;
    if (family == AF_INET6) {
        sockaddr_in6 target{};
        target.sin6_family = AF_INET6;
        target.sin6_port = htons(port);
        target.sin6_addr = in6addr_loopback;
        result = connect(
            socket_handle,
            reinterpret_cast<sockaddr*>(&target),
            sizeof(target));
    } else {
        sockaddr_in target{};
        target.sin_family = AF_INET;
        target.sin_port = htons(port);
        target.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        result = connect(
            socket_handle,
            reinterpret_cast<sockaddr*>(&target),
            sizeof(target));
    }
    if (result == SOCKET_ERROR) {
        closesocket(socket_handle);
        return INVALID_SOCKET;
    }
    return socket_handle;
}

int RunServer(
    unsigned short port,
    const std::string& marker,
    int family)
{
    SOCKET listener = socket(family, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) {
        return 10;
    }
    int bind_result = SOCKET_ERROR;
    if (family == AF_INET6) {
        sockaddr_in6 local{};
        local.sin6_family = AF_INET6;
        local.sin6_port = htons(port);
        local.sin6_addr = in6addr_loopback;
        bind_result = bind(
            listener,
            reinterpret_cast<sockaddr*>(&local),
            sizeof(local));
    } else {
        sockaddr_in local{};
        local.sin_family = AF_INET;
        local.sin_port = htons(port);
        local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        bind_result = bind(
            listener,
            reinterpret_cast<sockaddr*>(&local),
            sizeof(local));
    }
    if (bind_result == SOCKET_ERROR ||
        listen(listener, 16) == SOCKET_ERROR) {
        closesocket(listener);
        return 11;
    }
    std::cout << "SERVER_READY port=" << port
              << " family=" << (family == AF_INET6 ? "ipv6" : "ipv4")
              << " marker=" << marker << std::endl;
    SOCKET client = accept(listener, nullptr, nullptr);
    if (client == INVALID_SOCKET) {
        closesocket(listener);
        return 12;
    }
    char buffer[1024]{};
    recv(client, buffer, sizeof(buffer), 0);
    const std::string body = marker + "\n";
    const std::string response =
        "HTTP/1.1 200 OK\r\nContent-Length: " +
        std::to_string(body.size()) +
        "\r\nConnection: close\r\n\r\n" + body;
    send(
        client,
        response.data(),
        static_cast<int>(response.size()),
        0);
    shutdown(client, SD_BOTH);
    closesocket(client);
    closesocket(listener);
    std::cout << "SERVER_RESULT marker=" << marker << std::endl;
    return 0;
}

int RunClient(unsigned short port, int family) {
    SOCKET connection = ConnectLoopback(port, family);
    if (connection == INVALID_SOCKET) {
        std::cerr << "CLIENT_CONNECT_FAILED error=" << WSAGetLastError()
                  << "\n";
        return 20;
    }
    const char request[] =
        "GET http://example.invalid/ HTTP/1.1\r\n"
        "Host: example.invalid\r\n"
        "Connection: close\r\n\r\n";
    send(
        connection,
        request,
        static_cast<int>(sizeof(request) - 1),
        0);
    std::string response;
    char buffer[1024];
    for (;;) {
        const int received = recv(
            connection, buffer, sizeof(buffer), 0);
        if (received <= 0) {
            break;
        }
        response.append(buffer, buffer + received);
    }
    closesocket(connection);
    std::cout << "CLIENT_RESPONSE_BEGIN\n"
              << response
              << "\nCLIENT_RESPONSE_END\n";
    if (response.find("\r\n\r\nDIRECT\n") != std::string::npos) {
        std::cout << "CLIENT_RESULT=DIRECT\n";
        return 0;
    }
    if (response.find("\r\n\r\nPROXY\n") != std::string::npos) {
        std::cout << "CLIENT_RESULT=PROXY\n";
        return 30;
    }
    std::cout << "CLIENT_RESULT=UNKNOWN\n";
    return 31;
}

}  // namespace

int main(int argc, char** argv) {
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
        return 2;
    }
    int result = 2;
    if ((argc == 4 || argc == 5) &&
        std::string(argv[1]) == "server") {
        unsigned short port = 0;
        const int family = ParseFamily(argc == 5 ? argv[4] : "ipv4");
        if (ParsePort(argv[2], &port) && family != AF_UNSPEC) {
            result = RunServer(port, argv[3], family);
        }
    } else if ((argc == 3 || argc == 4) &&
               std::string(argv[1]) == "client") {
        unsigned short port = 0;
        const int family = ParseFamily(argc == 4 ? argv[3] : "ipv4");
        if (ParsePort(argv[2], &port) && family != AF_UNSPEC) {
            result = RunClient(port, family);
        }
    } else {
        std::cerr
            << "usage: loopback_smoke.exe server <port> <marker> [ipv4|ipv6]\n"
            << "       loopback_smoke.exe client <port> [ipv4|ipv6]\n";
    }
    WSACleanup();
    return result;
}
