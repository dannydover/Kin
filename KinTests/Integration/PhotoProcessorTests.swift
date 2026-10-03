import Foundation
import ImageIO
import UIKit
import Testing
@testable import Kin

@Suite("Photo snapshot processing") @MainActor struct PhotoProcessorTests {
    private func image(width: Int, height: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage!
    }
    private func jpeg(_ image: CGImage, properties: [CFString: Any] = [:]) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
    @Test("Malformed images fail without producing saved bytes", arguments: [Data(), Data([0, 1, 2, 3]), Data("not an image".utf8)])
    func malformedImagesFailWithoutProducingSavedBytes(_ bytes: Data) { #expect(PhotoProcessor.thumbnail(bytes) == nil) }
    @Test("Large photos retain aspect ratio within the 640 pixel limit") func largePhotosRetainAspectRatioWithin640PixelLimit() throws {
        let output = try #require(PhotoProcessor.thumbnail(jpeg(image(width: 1600, height: 800))))
        let result = try #require(UIImage(data: output)?.cgImage)
        #expect(result.width == 640)
        #expect(result.height == 320)
    }
    @Test("Photo orientation is baked into the saved pixels") func photoOrientationIsBakedIntoSavedPixels() throws {
        let input = try jpeg(image(width: 120, height: 80), properties: [kCGImagePropertyOrientation: 6])
        let output = try #require(PhotoProcessor.thumbnail(input))
        let result = try #require(UIImage(data: output))
        #expect(result.imageOrientation == .up)
        #expect(result.cgImage?.width == 80)
        #expect(result.cgImage?.height == 120)
    }
    @Test("Imported photo GPS metadata is removed") func importedPhotoGPSMetadataIsRemoved() throws {
        let input = try jpeg(image(width: 120, height: 80), properties: [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0, kCGImagePropertyGPSLongitude: 0, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitudeRef: "E"]])
        let originalSource = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        let originalProperties = try #require(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any])
        #expect(originalProperties[kCGImagePropertyGPSDictionary] != nil)
        let output = try #require(PhotoProcessor.thumbnail(input))
        let result = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }
}
