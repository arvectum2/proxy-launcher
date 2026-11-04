#if targetEnvironment(macCatalyst)
import SwiftUI

/// User-triggered repair for stale macOS NetworkExtension signing requirements.
/// Never deletes app data or other applications' VPN configurations.
struct MacVPNRepairControl: View {
    @ObservedObject var model: AppViewModel
    @State private var confirmRepair = false

    var body: some View {
        Button {
            confirmRepair = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise").frame(width: 24)
                Text("Восстановить VPN").fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Brand.text)
            .padding(16)
            .background(Brand.graphite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(model.vpn.isConnectedOrConnecting)
        .confirmationDialog(
            "Пересоздать системную конфигурацию VPN?",
            isPresented: $confirmRepair,
            titleVisibility: .visible
        ) {
            Button("Восстановить VPN", role: .destructive) {
                Task { await model.repairVPNConfiguration() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Прокси-профили и пароли сохранятся. macOS может снова запросить разрешение на VPN.")
        }
    }
}
#endif
