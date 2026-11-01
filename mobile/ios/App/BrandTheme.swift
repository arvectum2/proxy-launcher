import SwiftUI
import UIKit

/// Semantic iPhone appearance colors that follow dynamic device traits.
enum Brand {
    static let navy = Color(red: 0, green: 20/255, blue: 50/255)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let canvas = adaptive(
        light: UIColor(red: 0.957, green: 0.973, blue: 0.988, alpha: 1),
        dark: UIColor(red: 0, green: 20/255, blue: 50/255, alpha: 1)
    )
    static let graphite = adaptive(
        light: .white,
        dark: UIColor(red: 40/255, green: 50/255, blue: 70/255, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 0.918, green: 0.949, blue: 0.970, alpha: 1),
        dark: UIColor(red: 16/255, green: 40/255, blue: 70/255, alpha: 1)
    )
    static let text = adaptive(
        light: UIColor(red: 0.075, green: 0.133, blue: 0.220, alpha: 1),
        dark: .white
    )
    static let softGray = adaptive(
        light: UIColor(red: 0.290, green: 0.344, blue: 0.410, alpha: 1),
        dark: UIColor(red: 200/255, green: 210/255, blue: 220/255, alpha: 1)
    )
    static let mint = adaptive(
        light: UIColor(red: 0, green: 0.43, blue: 0.34, alpha: 1),
        dark: UIColor(red: 0, green: 200/255, blue: 160/255, alpha: 1)
    )
    static let mintLight = adaptive(
        light: UIColor(red: 0.008, green: 0.40, blue: 0.36, alpha: 1),
        dark: UIColor(red: 120/255, green: 250/255, blue: 230/255, alpha: 1)
    )
    static let actionText = adaptive(
        light: .white,
        dark: UIColor(red: 0, green: 20/255, blue: 50/255, alpha: 1)
    )
    // The original wordmark has light lettering.
    // Load the bundled PNG explicitly: SwiftUI named-image lookup can fail for
    // a standalone resource PNG not registered in an asset catalog.
    static var wordmark: Image {
        if let path = Bundle.main.path(forResource: "ArvectumWordmark", ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            return Image(uiImage: image)
        }
        return Image(systemName: "network")
    }
    // Crop only the original brand symbol; the full product title is one text style.
    static var symbol: Image {
        if let path = Bundle.main.path(forResource: "ArvectumWordmark", ofType: "png"),
           let image = UIImage(contentsOfFile: path),
           let original = image.cgImage,
           let cropped = original.cropping(to: CGRect(x: 0, y: 0, width: 182, height: 120)) {
            return Image(uiImage: UIImage(cgImage: cropped))
        }
        return Image(systemName: "network")
    }

    static let logoBacking = adaptive(
        light: UIColor(red: 0, green: 20/255, blue: 50/255, alpha: 1),
        dark: .clear
    )
}
