#include "routing_service_protocol.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <limits>

namespace arvectum::routing {
namespace {

constexpr const char* kOwnedResources[] = {
    "Arvectum.ProxyLauncher.WfpProvider",
    "Arvectum.ProxyLauncher.WfpSublayer",
    "Arvectum.ProxyLauncher.ConnectRedirectV4",
    "Arvectum.ProxyLauncher.ConnectRedirectV6",
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
            const unsigned char ch = static_cast<unsigned char>(*current_);
            if (ch < 0x20 || ch > 0x7e || ch == '\\') {
                return false;
            }
            if (output->size() >= max_length) {
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
            value = value * 10 + static_cast<unsigned>(*current_ - '0');
            if (value > std::numeric_limits<std::uint32_t>::max()) {
                return false;
            }
            ++current_;
        } while (current_ != end_ &&
                 std::isdigit(static_cast<unsigned char>(*current_)));
        *output = static_cast<std::uint32_t>(value);
        return true;
    }

private:
    const char* current_;
    const char* end_;
};

bool IsLowerHex(const std::string& value) noexcept {
    return !value.empty() &&
        std::all_of(value.begin(), value.end(), [](unsigned char ch) {
            return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f');
        });
}

bool IsRuleId(const std::string& value) noexcept {
    if (value.empty() || value.size() > 64 ||
        !std::isalnum(static_cast<unsigned char>(value.front()))) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
        return std::isalnum(ch) || ch == '.' || ch == '_' || ch == '-';
    });
}
bool IsSessionId(const std::string& value) noexcept {
    if (value.size() != 36) {
        return false;
    }
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (index == 8 || index == 13 || index == 18 || index == 23) {
            if (value[index] != '-') {
                return false;
            }
        } else if (!((value[index] >= '0' && value[index] <= '9') ||
                     (value[index] >= 'a' && value[index] <= 'f'))) {
            return false;
        }
    }
    return true;
}

bool IsDigest(const std::string& value) noexcept {
    return value.size() == 64 && IsLowerHex(value);
}

bool DecodeHex(
    const std::string& value,
    std::vector<unsigned char>* output) noexcept
{
    if (output == nullptr || value.empty() || (value.size() % 2) != 0 ||
        value.size() > 131072 || !IsLowerHex(value)) {
        return false;
    }
    output->clear();
    output->reserve(value.size() / 2);
    auto nibble = [](char ch) -> unsigned char {
        return ch <= '9'
            ? static_cast<unsigned char>(ch - '0')
            : static_cast<unsigned char>(ch - 'a' + 10);
    };
    for (std::size_t index = 0; index < value.size(); index += 2) {
        output->push_back(static_cast<unsigned char>(
            (nibble(value[index]) << 4) | nibble(value[index + 1])));
    }
    return true;
}

bool ParseFamilies(
    Cursor* cursor,
    ServiceFilterSpec* filter) noexcept
{
    if (cursor == nullptr || filter == nullptr || !cursor->Expect('[')) {
        return false;
    }
    std::uint32_t family = 0;
    if (!cursor->ReadUInt(&family) || (family != 4 && family != 6)) {
        return false;
    }
    filter->address_families.push_back(static_cast<unsigned short>(family));
    if (cursor->Expect(',')) {
        std::uint32_t second = 0;
        if (!cursor->ReadUInt(&second) ||
            (second != 4 && second != 6) || second == family) {
            return false;
        }
        filter->address_families.push_back(static_cast<unsigned short>(second));
    }
    return cursor->Expect(']');
}

bool ParseFilter(Cursor* cursor, ServiceFilterSpec* filter) noexcept {
    if (cursor == nullptr || filter == nullptr ||
        !cursor->ExpectText("{\"address_families\":")) {
        return false;
    }
    if (!ParseFamilies(cursor, filter) ||
        !cursor->ExpectText(",\"application_wfp_id_hex\":")) {
        return false;
    }
    std::string app_hex;
    if (!cursor->ReadString(&app_hex, 131072) ||
        !DecodeHex(app_hex, &filter->application_id) ||
        !cursor->ExpectText(",\"destination_kind\":")) {
        return false;
    }
    std::string destination_kind;
    if (!cursor->ReadString(&destination_kind, 8)) {
        return false;
    }
    if (destination_kind == "all") {
        filter->destination_kind = ServiceDestinationKind::kAll;
    } else if (destination_kind == "cidr") {
        filter->destination_kind = ServiceDestinationKind::kCidr;
    } else {
        return false;
    }
    if (!cursor->ExpectText(",\"destination_value\":") ||
        !cursor->ReadString(&filter->destination_value, 64) ||
        !cursor->ExpectText(",\"operation\":")) {
        return false;
    }
    std::string operation;
    if (!cursor->ReadString(&operation, 40)) {
        return false;
    }
    if (operation == "redirect_to_local_proxy") {
        filter->operation = ServiceFilterOperation::kRedirect;
    } else if (operation == "permit_bypass_arvectum_redirect") {
        filter->operation = ServiceFilterOperation::kBypass;
    } else {
        return false;
    }
    if (!cursor->ExpectText(",\"remote_port\":")) {
        return false;
    }
    std::uint32_t remote_port = 0;
    if (!cursor->ReadUInt(&remote_port) || remote_port > 65535 ||
        !cursor->ExpectText(",\"rule_id\":") ||
        !cursor->ReadString(&filter->rule_id, 64) ||
        !IsRuleId(filter->rule_id) || !cursor->Expect('}')) {
        return false;
    }
    filter->remote_port = static_cast<std::uint16_t>(remote_port);
    if (filter->destination_kind == ServiceDestinationKind::kAll) {
        return filter->destination_value == "*" &&
            filter->address_families.size() == 2 &&
            filter->address_families[0] == 4 &&
            filter->address_families[1] == 6;
    }
    return !filter->destination_value.empty() &&
        filter->address_families.size() == 1;
}

bool ParseFilters(
    Cursor* cursor,
    std::vector<ServiceFilterSpec>* filters) noexcept
{
    if (cursor == nullptr || filters == nullptr || !cursor->Expect('[')) {
        return false;
    }
    filters->clear();
    if (cursor->Expect(']')) {
        return true;
    }
    for (;;) {
        if (filters->size() >= kServiceMaxFilters) {
            return false;
        }
        ServiceFilterSpec filter{};
        if (!ParseFilter(cursor, &filter)) {
            return false;
        }
        filters->push_back(std::move(filter));
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
         index < (sizeof(kOwnedResources) / sizeof(kOwnedResources[0]));
         ++index) {
        std::string value;
        if (!cursor->ReadString(&value, 64) || value != kOwnedResources[index]) {
            return false;
        }
        if (index + 1 !=
                (sizeof(kOwnedResources) / sizeof(kOwnedResources[0])) &&
            !cursor->Expect(',')) {
            return false;
        }
    }
    return cursor->Expect(']');
}

bool ParseCommonTail(
    Cursor* cursor,
    ServiceRequest* request,
    bool apply) noexcept
{
    if (cursor == nullptr || request == nullptr ||
        !cursor->ExpectText(",\"owned_resources\":") ||
        !ParseOwnedResources(cursor) ||
        !cursor->ExpectText(",\"plan_digest\":") ||
        !cursor->ReadString(&request->plan_digest, 64) ||
        !IsDigest(request->plan_digest) ||
        !cursor->ExpectText(",\"protocol_version\":")) {
        return false;
    }
    std::uint32_t protocol = 0;
    if (!cursor->ReadUInt(&protocol) || protocol != kServiceProtocolVersion) {
        return false;
    }
    if (apply) {
        if (!cursor->ExpectText(",\"proxy\":{\"pid\":")) {
            return false;
        }
        std::uint32_t pid = 0;
        std::uint32_t port = 0;
        if (!cursor->ReadUInt(&pid) || pid == 0 ||
            !cursor->ExpectText(",\"port\":") ||
            !cursor->ReadUInt(&port) || port == 0 || port > 65535 ||
            !cursor->Expect('}')) {
            return false;
        }
        request->proxy_pid = pid;
        request->proxy_port = static_cast<std::uint16_t>(port);
    }
    if (!cursor->ExpectText(",\"session_id\":") ||
        !cursor->ReadString(&request->session_id, 36) ||
        !IsSessionId(request->session_id) ||
        !cursor->Expect('}') || !cursor->End()) {
        return false;
    }
    return true;
}

void AppendResources(std::string* response) {
    response->append("[");
    for (std::size_t index = 0;
         index < (sizeof(kOwnedResources) / sizeof(kOwnedResources[0]));
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
    if (data == nullptr || request == nullptr || size == 0 ||
        size > 1024 * 1024) {
        if (error != nullptr) {
            *error = "invalid request frame";
        }
        return false;
    }
    *request = ServiceRequest{};
    Cursor cursor(data, size);
    if (!cursor.ExpectText("{\"command\":")) {
        if (error != nullptr) {
            *error = "non-canonical request";
        }
        return false;
    }
    std::string command;
    if (!cursor.ReadString(&command, 16)) {
        if (error != nullptr) {
            *error = "invalid command";
        }
        return false;
    }
    if (command == "apply_plan") {
        request->command = ServiceCommand::kApplyPlan;
        if (!cursor.ExpectText(",\"filters\":") ||
            !ParseFilters(&cursor, &request->filters) ||
            request->filters.empty() ||
            !ParseCommonTail(&cursor, request, true)) {
            if (error != nullptr) {
                *error = "invalid apply request";
            }
            return false;
        }
        return true;
    }
    if (command == "restore") {
        request->command = ServiceCommand::kRestore;
        if (!ParseCommonTail(&cursor, request, false)) {
            if (error != nullptr) {
                *error = "invalid restore request";
            }
            return false;
        }
        return true;
    }
    if (error != nullptr) {
        *error = "unsupported command";
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
    const char* command = restore ? "restore" : "apply_plan";
    std::string response = "{";
    if (ok && !restore) {
        response += "\"applied_resources\":";
        AppendResources(&response);
        response += ",";
    }
    response += "\"command\":\"";
    response += command;
    response += "\",\"plan_digest\":\"";
    response += request.plan_digest;
    response += "\",\"protocol_version\":";
    response += std::to_string(kServiceProtocolVersion);
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
        response += error != nullptr ? error : "native routing failure";
        response += "\"";
    }
    response += "}";
    return response;
}

}  // namespace arvectum::routing
