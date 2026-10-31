import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import XCTest

/// Verifies the real iPhone barcode image decoder and the production import
/// validation together. This is an optical-fixture substitute, NOT proof that
/// a physical camera saw a QR pattern on another device.
final class PhysicalQRCodeDecodeUITests: XCTestCase {
    private func decodedText(_ input: String) throws -> String {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(input.utf8)
        generator.correctionLevel = "H"
        let transformed = try XCTUnwrap(generator.outputImage).transformed(by: CGAffineTransform(scaleX: 9, y: 9))
        let image = try XCTUnwrap(CIContext().createCGImage(transformed, from: transformed.extent))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observation = try XCTUnwrap(request.results?.first)
        XCTAssertEqual(observation.symbology, .qr)
        return try XCTUnwrap(observation.payloadStringValue)
    }

    func testImageQRToProductionProxyImporterOnPhysicalIPhone() throws {
        let original = "socks5://fixture:q%40a@proxy.example.com:1080#QR-physical-QA"
        let decoded = try decodedText(original)
        XCTAssertEqual(decoded, original)
        let result = try XCTUnwrap(ProxyImport.parse(decoded).first)
        XCTAssertEqual(result.type, .socks5)
        XCTAssertEqual(result.host, "proxy.example.com")
        XCTAssertEqual(result.port, 1080)
        XCTAssertEqual(result.username, "fixture")
        XCTAssertEqual(result.password, "q@a")
    }

    func testUnsupportedQRPayloadRejectedOnPhysicalIPhone() throws {
        let decoded = try decodedText("vless://invalid@proxy.example.com:443")
        XCTAssertThrowsError(try ProxyImport.parse(decoded))
    }
}
