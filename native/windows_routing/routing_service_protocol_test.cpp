#include "routing_service_protocol.h"

#include <iostream>
#include <string>

namespace {

const char kResources[] =
    "\"owned_resources\":["
    "\"Arvectum.ProxyLauncher.WfpProvider\","
    "\"Arvectum.ProxyLauncher.WfpSublayer\","
    "\"Arvectum.ProxyLauncher.ConnectRedirectV4\","
    "\"Arvectum.ProxyLauncher.ConnectRedirectV6\"]";

bool Parse(
    const std::string& json,
    arvectum::routing::ServiceRequest* request = nullptr)
{
    arvectum::routing::ServiceRequest local{};
    std::string error;
    const bool ok = arvectum::routing::ParseServiceRequest(
        reinterpret_cast<const unsigned char*>(json.data()),
        json.size(),
        request != nullptr ? request : &local,
        &error);
    if (!ok) {
        std::cerr << "parse rejected: " << error << "\n";
    }
    return ok;
}
std::string ApplyRequest() {
    return std::string(
        "{\"command\":\"apply_plan\",\"filters\":["
        "{\"address_families\":[4,6],"
        "\"application_wfp_id_hex\":\"0102\","
        "\"destination_kind\":\"all\","
        "\"destination_value\":\"*\","
        "\"operation\":\"redirect_to_local_proxy\","
        "\"remote_port\":8080,"
        "\"rule_id\":\"browser-proxy\"}],") +
        kResources +
        ",\"plan_digest\":\"" + std::string(64, 'a') +
        "\",\"protocol_version\":3,"
        "\"proxy\":{\"pid\":4242,\"port\":18080},"
        "\"session_id\":\"11111111-1111-4111-8111-111111111111\"}";
}

std::string RestoreRequest() {
    return std::string("{\"command\":\"restore\",") +
        kResources +
        ",\"plan_digest\":\"" + std::string(64, 'b') +
        "\",\"protocol_version\":3,"
        "\"session_id\":\"22222222-2222-4222-8222-222222222222\"}";
}
bool Expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

}  // namespace

int main() {
    bool pass = true;

    arvectum::routing::ServiceRequest apply{};
    pass &= Expect(Parse(ApplyRequest(), &apply), "valid apply request");
    pass &= Expect(
        apply.command == arvectum::routing::ServiceCommand::kApplyPlan,
        "apply command");
    pass &= Expect(apply.proxy_pid == 4242, "proxy pid");
    pass &= Expect(apply.proxy_port == 18080, "proxy port");
    pass &= Expect(apply.filters[0].remote_port == 8080, "filter remote port");
    pass &= Expect(apply.filters.size() == 1, "single filter");
    if (!apply.filters.empty()) {
        pass &= Expect(
            apply.filters[0].application_id.size() == 2,
            "decoded app id");
    }
    arvectum::routing::ServiceRequest restore{};
    pass &= Expect(Parse(RestoreRequest(), &restore), "valid restore request");
    pass &= Expect(
        restore.command == arvectum::routing::ServiceCommand::kRestore,
        "restore command");

    std::string extra = ApplyRequest();
    extra.insert(extra.size() - 1, ",\"unexpected\":1");
    pass &= Expect(!Parse(extra), "unknown field rejected");

    std::string foreign = ApplyRequest();
    const std::string owned = "Arvectum.ProxyLauncher.WfpProvider";
    const std::size_t owned_at = foreign.find(owned);
    if (owned_at != std::string::npos) {
        foreign.replace(owned_at, owned.size(), "Foreign.WfpProvider");
    }
    pass &= Expect(!Parse(foreign), "foreign resource rejected");

    std::string escaped = ApplyRequest();
    const std::string rule = "browser-proxy";
    const std::size_t rule_at = escaped.find(rule);
    if (rule_at != std::string::npos) {
        escaped.replace(rule_at, rule.size(), "browser\\u002dproxy");
    }
    pass &= Expect(!Parse(escaped), "escaped token rejected");
    std::string wrong_protocol = ApplyRequest();
    const std::string protocol = "\"protocol_version\":3";
    const std::size_t protocol_at = wrong_protocol.find(protocol);
    if (protocol_at != std::string::npos) {
        wrong_protocol.replace(
            protocol_at,
            protocol.size(),
            "\"protocol_version\":1");
    }
    pass &= Expect(!Parse(wrong_protocol), "old protocol rejected");

    if (!pass) {
        return 1;
    }
    std::cout << "ARVECTUM_ROUTING_SERVICE_PROTOCOL_TEST_PASS\n";
    return 0;
}
