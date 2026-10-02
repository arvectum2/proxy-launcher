#include "windivert_service_protocol.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

bool Expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL " << message << "\n";
        return false;
    }
    return true;
}

bool Parse(
    const std::string& text,
    arvectum::windivert::ServiceRequest* request)
{
    std::string error;
    const bool ok = arvectum::windivert::ParseServiceRequest(
        reinterpret_cast<const unsigned char*>(text.data()),
        text.size(),
        request,
        &error);
    if (!ok) {
        std::cerr << "parse error: " << error << "\n";
    }
    return ok;
}

std::string ApplyJson() {
    const std::string hash(64, 'a');
    const std::string digest(64, 'b');
    return
        "{\"applications\":["
        "{\"application_path_sha256\":\"" + hash +
        "\",\"local_proxy_port\":8080,"
        "\"rule_id\":\"app-exclusion-a\"}],"
        "\"command\":\"apply_plan\","
        "\"owned_resources\":["
        "\"Arvectum.ProxyLauncher.WinDivert.SocketTracker\","
        "\"Arvectum.ProxyLauncher.WinDivert.NetworkTranslator\"],"
        "\"plan_digest\":\"" + digest + "\","
        "\"protocol_version\":1,"
        "\"proxy\":{\"direct_listener_port\":49152,\"pid\":1234},"
        "\"session_id\":"
        "\"11111111-1111-4111-8111-111111111111\"}";
}

std::string RestoreJson() {
    const std::string digest(64, 'b');
    return
        "{\"command\":\"restore\","
        "\"owned_resources\":["
        "\"Arvectum.ProxyLauncher.WinDivert.SocketTracker\","
        "\"Arvectum.ProxyLauncher.WinDivert.NetworkTranslator\"],"
        "\"plan_digest\":\"" + digest + "\","
        "\"protocol_version\":1,"
        "\"session_id\":"
        "\"11111111-1111-4111-8111-111111111111\"}";
}

}  // namespace

int main() {
    using namespace arvectum::windivert;
    bool ok = true;

    ServiceRequest apply{};
    ok = Expect(Parse(ApplyJson(), &apply), "apply parse") && ok;
    ok = Expect(
        apply.command == ServiceCommand::kApplyPlan,
        "apply command") && ok;
    ok = Expect(apply.applications.size() == 1, "application count") && ok;
    ok = Expect(
        apply.applications[0].application_path_sha256 ==
            std::string(64, 'a'),
        "application hash") && ok;
    ok = Expect(
        apply.applications[0].local_proxy_port == 8080,
        "proxy port") && ok;
    ok = Expect(apply.direct_listener_port == 49152, "direct port") && ok;
    ok = Expect(apply.proxy_pid == 1234, "proxy pid") && ok;

    const std::string response = BuildServiceResponse(
        apply, true, nullptr, false, false);
    ok = Expect(
        response.find("\"status\":\"ok\"") != std::string::npos,
        "apply response status") && ok;
    ok = Expect(
        response.find("WinDivert.SocketTracker") != std::string::npos,
        "apply response resources") && ok;

    ServiceRequest restore{};
    ok = Expect(Parse(RestoreJson(), &restore), "restore parse") && ok;
    ok = Expect(
        restore.command == ServiceCommand::kRestore,
        "restore command") && ok;
    const std::string restored = BuildServiceResponse(
        restore, true, nullptr, true, true);
    ok = Expect(
        restored.find(
            "\"remaining_owned_resources\":[]") != std::string::npos,
        "restore remaining") && ok;
    ok = Expect(
        restored.find(
            "\"removed_resources\":["
            "\"Arvectum.ProxyLauncher.WinDivert.SocketTracker\"") !=
            std::string::npos,
        "restore removed") && ok;

    std::string wrong_resource = ApplyJson();
    const std::string expected =
        "Arvectum.ProxyLauncher.WinDivert.SocketTracker";
    const std::size_t resource_at = wrong_resource.find(expected);
    if (resource_at != std::string::npos) {
        wrong_resource.replace(
            resource_at, expected.size(),
            "Arvectum.ProxyLauncher.WinDivert.WrongResource");
    }
    ServiceRequest rejected{};
    ok = Expect(
        !Parse(wrong_resource, &rejected),
        "reject wrong resources") && ok;

    std::string collision = ApplyJson();
    const std::string direct =
        "\"direct_listener_port\":49152";
    const std::size_t direct_at = collision.find(direct);
    if (direct_at != std::string::npos) {
        collision.replace(
            direct_at, direct.size(),
            "\"direct_listener_port\":8080");
    }
    ok = Expect(
        !Parse(collision, &rejected),
        "reject port collision") && ok;

    if (!ok) {
        return EXIT_FAILURE;
    }
    std::cout << "WINDIVERT_SERVICE_PROTOCOL_PASS\n";
    return EXIT_SUCCESS;
}
