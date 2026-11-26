#if APL_NATIVE_RELEASE_LINK_PREPARATION
#if DEBUG || APL_NATIVE_SYNTHETIC_RUNTIME || APL_NATIVE_PRODUCT_RUNTIME_REVIEW || APL_NATIVE_RUNTIME_QA_HARNESS || APL_NATIVE_RUNTIME_QA_DIAGNOSTICS
#error("Release link preparation must never include a laboratory start path")
#endif
#if !APL_NATIVE_PROVIDER_INTEGRATION || !APL_NATIVE_XRAY_CANDIDATE || !APL_NATIVE_AWG_CANDIDATE || !APL_NATIVE_UNIFIED_GO_CANDIDATE || !APL_NATIVE_AWG_PRODUCT_BRIDGE
#error("Release link preparation requires both product driver modules")
#endif
// Type-check both real driver interfaces in Release. No caller or VPN
// activation is introduced here; the ordinary provider still denies native starts.
import Foundation
import NetworkExtension

private func verifyProductDriverTypes(_ driver: NativeXrayRuntimeDriver,
                                      _ flow: NativeAWGProductFlow,
                                      _ owner: NativeCredentialHandoff.Binding,
                                      _ route: NativeValidationRoute,
                                      _ configuration: Data) {
    let _: (NativeValidationRoute, Data) throws -> Void = driver.validate
    let _: (NativeCredentialHandoff.Binding, NativeValidationRoute, Data) throws -> Void = driver.startXray
    let _: (Data, @escaping (Bool) -> Void) -> Void = flow.start
    let _ = (owner, route, configuration)
}
#endif
