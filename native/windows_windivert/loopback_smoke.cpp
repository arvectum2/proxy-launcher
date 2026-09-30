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

SOCKET ConnectLoopback(unsigned short port) {
    SOCKET socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET) {
        return INVALID_SOCKET;
    }
    sockaddr_in target{};
    target.sin_family = AF_INET;
    target.sin_port = htons(port);
    target.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(
            socket_handle,
            reinterpret_cast<sockaddr*>(&target),
            sizeof(target)) == SOCKET_ERROR) {
        closesocket(socket_handle);
        return INVALID_SOCKET;
    }
    return socket_handle;
}

int RunServer(unsigned short port, const std::string& marker) {
    SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) {
        return 10;
    }
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_port = htons(port);
    local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(
            listener,
            reinterpret_cast<sockaddr*>(&local),
            sizeof(local)) == SOCKET_ERROR ||
        listen(listener, 16) == SOCKET_ERROR) {
        closesocket(listener);
        return 11;
    }
    std::cout << "SERVER_READY port=" << port
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

int RunClient(unsigned short port) {
    SOCKET connection = ConnectLoopback(port);
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
    if (argc == 4 && std::string(argv[1]) == "server") {
        unsigned short port = 0;
        if (ParsePort(argv[2], &port)) {
            result = RunServer(port, argv[3]);
        }
    } else if (argc == 3 && std::string(argv[1]) == "client") {
        unsigned short port = 0;
        if (ParsePort(argv[2], &port)) {
            result = RunClient(port);
        }
    } else {
        std::cerr
            << "usage: loopback_smoke.exe server <port> <marker>\n"
            << "       loopback_smoke.exe client <port>\n";
    }
    WSACleanup();
    return result;
}
