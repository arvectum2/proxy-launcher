import Foundation
import SwiftUI

/// Lightweight frame instrumentation for real iOS Simulator screenshots.
/// It has no effect except when -aplHomeLayoutProbe is passed in DEBUG builds.
struct HomeFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, incoming in incoming })
    }
}

extension View {
    func homeMeasured(_ name: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: HomeFramePreference.self,
                                       value: [name: proxy.frame(in: .named("APLHome"))])
            }
        }
    }
}

enum HomeLayoutProbe {
    static func save(_ frames: [String: CGRect], language: String, width: CGFloat, height: CGFloat) {
#if DEBUG
        guard frames["header"] != nil, frames["connection"] != nil,
              frames["profile"] != nil, frames["primaryAction"] != nil,
              frames["banner"] != nil else { return }
        var json: [String: Any] = ["language": language, "width": width,
                                   "height": height, "bannerVisible": true]
        var rectangles: [String: [String: CGFloat]] = [:]
        for (name, rect) in frames {
            rectangles[name] = ["x": rect.minX, "y": rect.minY,
                                "width": rect.width, "height": rect.height]
        }
        json["frames"] = rectangles
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .sortedKeys),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: folder.appendingPathComponent("APLHomeLayoutQA.json"), options: .atomic)
#endif
    }
}
