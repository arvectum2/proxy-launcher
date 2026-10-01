#include "windivert_service_protocol.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <limits>

namespace arvectum::windivert {
namespace {

constexpr const char* kOwnedResources[] = {
    "Arvectum.ProxyLauncher.WinDivert.SocketTracker",
    "Arvectum.ProxyLauncher.WinDivert.NetworkTranslator",
};

class Cursor {
public:
    Cursor(const unsigned char* data, std::size_t size)
        : current_(reinterpret_cast<const char*>(data)),
          end_(reinterpret_cast<const char*>(data) + size) {}

    bool End() const noexcept { return current_ == end_; }

    bool Expect(char value) noexcept {
        if (current_ == end_ || *current_ != value) {
            return false;
        }
        ++current_;
        return true;
    }

    bool ExpectText(const char* value) noexcept {
        const std::size_t length = std::strlen(value);
        if (static_cast<std::size_t>(end_ - current_) < length ||
            std::memcmp(current_, value, length) != 0) {
            return false;
        }
        current_ += length;
        return true;
    }

    bool ReadString(std::string* output, std::size_t max_length) noexcept {
        if (output == nullptr || !Expect('"')) {
            return false;
        }
        output->clear();
        while (current_ != end_ && *current_ != '"') {
            const unsigned char ch =
                static_cast<unsigned char>(*current_);
            if (ch < 0x20 || ch > 0x7e || ch == '\\' ||
                output->size() >= max_length) {
                return false;
            }
            output->push_back(*current_++);
        }
        return Expect('"');
    }

    bool ReadUInt(std::uint32_t* output) noexcept {
        if (output == nullptr || current_ == end_ ||
            !std::isdigit(static_cast<unsigned char>(*current_))) {
            return false;
        }
        std::uint64_t value = 0;
        do {
            value = value * 10 +
                static_cast<unsigned>(*current_ - '0');
            if (value > std::numeric_limits<std::uint32_t>::max()) {
                return false;
            }
            ++current_;
        } while (
            current_ != end_ &&
            std::isdigit(static_cast<unsigned char>(*current_)));
        *output = static_cast<std::uint32_t>(value);
        return true;
    }

private:
    const char* current_;
    const char* end_;
};

bool IsLowerHex(
    const std::string& value,
    std::size_t exact_length) noexcept
{
    return value.size() == exact_length &&
        std::all_of(value.begin(), value.end(), [](unsigned char ch) {
            return (ch >= '0' && ch <= '9') ||
                (ch >= 'a' && ch <= 'f');
        });
}

bool IsRuleId(const std::string& value) noexcept {
    if (value.empty() || value.size() > 64 ||
        !std::isalnum(static_cast<unsigned char>(value.front()))) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
        return std::isalnum(ch) ||
            ch == '.' || ch == '_' || ch == '-';
    });
}

bool IsSessionId(const std::string& value) noexcept {
    if (value.size() != 36) {
        return false;
    }
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (index == 8 || index == 13 ||
            index == 18 || index == 23) {
            if (value[index] != '-') {
                return false;
            }
        } else if (!std::isxdigit(
                       static_cast<unsigned char>(value[index])) ||
                   std::isupper(
                       static_cast<unsigned char>(value[index]))) {
            return false;
        }
    }
    return true;
}

bool ParseApplication(
    Cursor* cursor,
    ApplicationSpec* application) noexcept
{
    if (cursor == nullptr || application == nullptr ||
        !cursor->ExpectText(
            "{\"application_path_sha256\":")) {
        return false;
    }
    if (!cursor->ReadString(
            &application->application_path_sha256, 64) ||
        !IsLowerHex(application->application_path_sha256, 64) ||
        !cursor->ExpectText(",\"local_proxy_port\":")) {
        return false;
    }
    std::uint32_t port = 0;
    if (!cursor->ReadUInt(&port) || port == 0 || port > 65535 ||
        !cursor->ExpectText(",\"rule_id\":") ||
        !cursor->ReadString(&application->rule_id, 64) ||
        !IsRuleId(application->rule_id) ||
        !cursor->Expect('}')) {
        return false;
    }
    application->local_proxy_port =
        static_cast<std::uint16_t>(port);
    return true;
}

bool ParseApplications(
    Cursor* cursor,
    std::vector<ApplicationSpec>* applications,
    std::uint16_t* proxy_port) noexcept
{
    if (cursor == nullptr || applications == nullptr ||
        proxy_port == nullptr || !cursor->Expect('[')) {
        return false;
    }
    applications->clear();
    *proxy_port = 0;
    if (cursor->Expect(']')) {
        return false;
    }
    for (;;) {
        if (applications->size() >= kMaxApplications) {
            return false;
        }
        ApplicationSpec application{};
        if (!ParseApplication(cursor, &application)) {
            return false;
        }
        if (*proxy_port == 0) {
            *proxy_port = application.local_proxy_port;
        } else if (*proxy_port != application.local_proxy_port) {
            return false;
        }
        applications->push_back(std::move(application));
        if (cursor->Expect(']')) {
            return true;
        }
        if (!cursor->Expect(',')) {
            return false;
        }
    }
}

bool ParseOwnedResources(Cursor* cursor) noexcept {
    if (cursor == nullptr || !cursor->Expect('[')) {
        return false;
    }
    for (std::size_t index = 0;
         index < sizeof(kOwnedResources) / sizeof(kOwnedResources[0]);
         ++index) {
        std::string value;
        if (!cursor->ReadString(&value, 64) ||
            value != kOwnedResources[index]) {
            return false;
        }
        if (index + 1 !=
                sizeof(kOwnedResources) / sizeof(kOwnedResources[0]) &&
            !cursor->Expect(',')) {
            return false;
        }
    }
    return cursor->Expect(']');
}

bool ParseProtocolAndSession(
    Cursor* cursor,
    ServiceRequest* request) noexcept
{
    if (!cursor->ExpectText(",\"plan_digest\":") ||
        !cursor->ReadString(&request->plan_digest, 64) ||
        !IsLowerHex(request->plan_digest, 64) ||
        !cursor->ExpectText(",\"protocol_version\":")) {
        return false;
    }
    std::uint32_t version = 0;
    if (!cursor->ReadUInt(&version) ||
        version != kProtocolVersion ||
        !cursor->ExpectText(",\"session_id\":") ||
        !cursor->ReadString(&request->session_id, 36) ||
        !IsSessionId(request->session_id) ||
        !cursor->Expect('}') || !cursor->End()) {
        return false;
    }
    return true;
}

bool ParseApply(
    Cursor* cursor,
    ServiceRequest* request) noexcept
{
    std::uint16_t proxy_port = 0;
    if (!cursor->ExpectText("{\"applications\":") ||
        !ParseApplications(
            cursor, &request->applications, &proxy_port) ||
        !cursor->ExpectText(
            ",\"command\":\"apply_plan\","
            "\"owned_resources\":") ||
        !ParseOwnedResources(cursor) ||
        !cursor->ExpectText(",\"plan_digest\":") ||
        !cursor->ReadString(&request->plan_digest, 64) ||
        !IsLowerHex(request->plan_digest, 64) ||
        !cursor->ExpectText(",\"protocol_version\":")) {
        return false;
    }
    std::uint32_t version = 0;
    std::uint32_t direct_port = 0;
    std::uint32_t pid = 0;
    if (!cursor->ReadUInt(&version) ||
        version != kProtocolVersion ||
        !cursor->ExpectText(
            ",\"proxy\":{\"direct_listener_port\":") ||
        !cursor->ReadUInt(&direct_port) ||
        direct_port == 0 || direct_port > 65535 ||
        direct_port == proxy_port ||
        !cursor->ExpectText(",\"pid\":") ||
        !cursor->ReadUInt(&pid) || pid == 0 ||
        !cursor->ExpectText("},\"session_id\":") ||
        !cursor->ReadString(&request->session_id, 36) ||
        !IsSessionId(request->session_id) ||
        !cursor->Expect('}') || !cursor->End()) {
        return false;
    }
    request->proxy_pid = pid;
    request->direct_listener_port =
        static_cast<std::uint16_t>(direct_port);
    return true;
}

bool ParseRestore(
    Cursor* cursor,
    ServiceRequest* request) noexcept
{
    if (!cursor->ExpectText(
            "{\"command\":\"restore\","
            "\"owned_resources\":") ||
        !ParseOwnedResources(cursor)) {
        return false;
    }
    return ParseProtocolAndSession(cursor, request);
}

void AppendResources(std::string* response) {
    response->append("[");
    for (std::size_t index = 0;
         index < sizeof(kOwnedResources) / sizeof(kOwnedResources[0]);
         ++index) {
        if (index != 0) {
            response->append(",");
        }
        response->append("\"");
        response->append(kOwnedResources[index]);
        response->append("\"");
    }
    response->append("]");
}

std::string SafeError(const char* error) {
    std::string result;
    const char* cursor =
        error == nullptr ? "WinDivert routing failure" : error;
    while (*cursor != '\0' && result.size() < 256) {
        const unsigned char ch =
            static_cast<unsigned char>(*cursor++);
        if (ch >= 0x20 && ch <= 0x7e &&
            ch != '"' && ch != '\\') {
            result.push_back(static_cast<char>(ch));
        }
    }
    return result.empty()
        ? "WinDivert routing failure"
        : result;
}

}  // namespace

bool ParseServiceRequest(
    const unsigned char* data,
    std::size_t size,
    ServiceRequest* request,
    std::string* error) noexcept
{
    if (error != nullptr) {
        error->clear();
    }
    if (data == nullptr || request == nullptr ||
        size == 0 || size > 1024 * 1024) {
        if (error != nullptr) {
            *error = "invalid request frame";
        }
        return false;
    }
    *request = ServiceRequest{};
    Cursor cursor(data, size);
    if (size > 20 &&
        std::memcmp(data, "{\"applications\":", 16) == 0) {
        request->command = ServiceCommand::kApplyPlan;
        if (ParseApply(&cursor, request)) {
            return true;
        }
        if (error != nullptr) {
            *error = "invalid apply request";
        }
        return false;
    }
    request->command = ServiceCommand::kRestore;
    if (ParseRestore(&cursor, request)) {
        return true;
    }
    if (error != nullptr) {
        *error = "invalid restore request";
    }
    return false;
}

std::string BuildServiceResponse(
    const ServiceRequest& request,
    bool ok,
    const char* error,
    bool restore,
    bool resources_verified)
{
    std::string response = "{";
    if (ok && !restore) {
        response += "\"applied_resources\":";
        AppendResources(&response);
        response += ",";
    }
    response += "\"command\":\"";
    response += restore ? "restore" : "apply_plan";
    response += "\",\"plan_digest\":\"";
    response += request.plan_digest;
    response += "\",\"protocol_version\":";
    response += std::to_string(kProtocolVersion);
    response += ",";
    if (ok && restore) {
        response += "\"remaining_owned_resources\":";
        if (resources_verified) {
            response += "[]";
        } else {
            AppendResources(&response);
        }
        response += ",\"removed_resources\":";
        if (resources_verified) {
            AppendResources(&response);
        } else {
            response += "[]";
        }
        response += ",";
    }
    response += "\"session_id\":\"";
    response += request.session_id;
    response += "\",\"status\":\"";
    response += ok ? "ok" : "error";
    response += "\"";
    if (!ok) {
        response += ",\"error\":\"";
        response += SafeError(error);
        response += "\"";
    }
    response += "}";
    return response;
}

}  // namespace arvectum::windivert

