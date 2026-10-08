import Foundation
import ImageIO

struct ImageMetadataField: Identifiable, Sendable {
    let name: String; let value: String
    var id: String { name }
}
struct ImageMetadataSection: Identifiable, Sendable {
    let title: String; let fields: [ImageMetadataField]
    var id: String { title }
}
struct ImageMetadata: Sendable {
    let imageFields: [ImageMetadataField]
    let exifFields: [ImageMetadataField]
    let gpsFields: [ImageMetadataField]
    let additional: [ImageMetadataSection]
    let hasExif: Bool

    static func read(_ url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil) as? [String: Any] else {
            throw FileProviderError.other("Couldn't read this image's metadata.")
        }
        return parse(properties)
    }
    static func parse(_ properties: [String: Any]) -> ImageMetadata {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        var image: [ImageMetadataField] = [], camera: [ImageMetadataField] = [], location: [ImageMetadataField] = []
        // ImageIO synthesizes EXIF dimensions even for PNGs with no camera metadata.
        let basicExif = Set([kCGImagePropertyExifPixelXDimension as String, kCGImagePropertyExifPixelYDimension as String])
        var usedExif = basicExif, usedAux = Set<String>(), usedTIFF = Set([kCGImagePropertyTIFFOrientation as String]), usedGPS = Set<String>()
        func append(_ name: String, _ value: String?, to fields: inout [ImageMetadataField]) {
            if let value, !value.isEmpty { fields.append(ImageMetadataField(name: name, value: value)) }
        }
        if let width = number(properties[kCGImagePropertyPixelWidth as String]), let height = number(properties[kCGImagePropertyPixelHeight as String]) { append("Dimensions", decimal(width, digits: 0) + " × " + decimal(height, digits: 0), to: &image) }
        append("Color Model", display(properties[kCGImagePropertyColorModel as String]), to: &image)
        append("Color Profile", display(properties[kCGImagePropertyProfileName as String]), to: &image)
        if let depth = number(properties[kCGImagePropertyDepth as String]) { append("Bit Depth", decimal(depth, digits: 0) + " bits", to: &image) }
        if let dpi = number(properties[kCGImagePropertyDPIWidth as String]) { append("Resolution", decimal(dpi) + " dpi", to: &image) }
        if let orientation = number(properties[kCGImagePropertyOrientation as String]) {
            let labels = [1: "Normal", 2: "Mirrored horizontally", 3: "180°", 4: "Mirrored vertically", 5: "90° clockwise, mirrored", 6: "90° clockwise", 7: "90° counterclockwise, mirrored", 8: "90° counterclockwise"]
            append("Orientation", Int(exactly: orientation).flatMap { labels[$0] } ?? decimal(orientation), to: &image)
        }
        for (key, label) in [(kCGImagePropertyTIFFMake, "Camera Make"), (kCGImagePropertyTIFFModel, "Camera Model")] {
            let key = key as String; append(label, display(tiff[key]), to: &camera); usedTIFF.insert(key)
        }
        let lensKey = kCGImagePropertyExifLensModel as String
        append("Lens", display(exif[lensKey]) ?? display(aux[kCGImagePropertyExifAuxLensModel as String]), to: &camera)
        usedExif.insert(lensKey); usedAux.insert(kCGImagePropertyExifAuxLensModel as String)
        let dateKey = kCGImagePropertyExifDateTimeOriginal as String, offsetKey = kCGImagePropertyExifOffsetTimeOriginal as String
        if let date = display(exif[dateKey]) ?? display(tiff[kCGImagePropertyTIFFDateTime as String]) {
            append("Date Taken", date + (display(exif[offsetKey]).map { " " + $0 } ?? ""), to: &camera)
        }
        usedExif.formUnion([dateKey, offsetKey]); usedTIFF.insert(kCGImagePropertyTIFFDateTime as String)
        let exposureKey = kCGImagePropertyExifExposureTime as String
        if let seconds = number(exif[exposureKey]), seconds > 0 {
            append("Exposure Time", exposure(seconds), to: &camera)
        } else if let apex = number(exif[kCGImagePropertyExifShutterSpeedValue as String]) {
            let seconds = pow(2, -apex)
            if seconds.isFinite && seconds > 0 { append("Exposure Time", exposure(seconds), to: &camera) }
        }
        usedExif.insert(exposureKey)
        let apertureKey = kCGImagePropertyExifFNumber as String
        if let aperture = number(exif[apertureKey]) { append("Aperture", "f/" + decimal(aperture), to: &camera) }; usedExif.insert(apertureKey)
        let isoKey = kCGImagePropertyExifISOSpeedRatings as String
        append("ISO", display(exif[isoKey]) ?? display(exif[kCGImagePropertyExifISOSpeed as String]), to: &camera); usedExif.insert(isoKey)
        for (key, label, unit) in [(kCGImagePropertyExifFocalLength, "Focal Length", " mm"), (kCGImagePropertyExifFocalLenIn35mmFilm, "35 mm Equivalent", " mm"), (kCGImagePropertyExifExposureBiasValue, "Exposure Compensation", " EV")] {
            let key = key as String
            if let value = number(exif[key]) { append(label, decimal(value) + unit, to: &camera) }; usedExif.insert(key)
        }
        let flashKey = kCGImagePropertyExifFlash as String
        if let value = number(exif[flashKey]), let flash = Int(exactly: value) { append("Flash", flash & 1 == 1 ? "Fired" : "Did not fire", to: &camera) }
        // Keep the raw flash bitmask in additional EXIF because it carries more detail.
        let whiteBalanceKey = kCGImagePropertyExifWhiteBalance as String
        if let balance = number(exif[whiteBalanceKey]) { append("White Balance", balance == 0 ? "Auto" : "Manual", to: &camera) }; usedExif.insert(whiteBalanceKey)
        for (key, reference, label) in [(kCGImagePropertyGPSLatitude, kCGImagePropertyGPSLatitudeRef, "Latitude"), (kCGImagePropertyGPSLongitude, kCGImagePropertyGPSLongitudeRef, "Longitude")] {
            let key = key as String, reference = reference as String
            if let value = number(gps[key]) {
                let ref = display(gps[reference])?.uppercased()
                let signed = ref == "S" || ref == "W" ? -abs(value) : ref == "N" || ref == "E" ? abs(value) : value
                append(label, decimal(signed, digits: 6) + "°", to: &location)
            }; usedGPS.formUnion([key, reference])
        }
        if let altitude = number(gps[kCGImagePropertyGPSAltitude as String]) {
            let belowSeaLevel = number(gps[kCGImagePropertyGPSAltitudeRef as String]) == 1
            append("Altitude", decimal(belowSeaLevel ? -abs(altitude) : altitude) + " m", to: &location)
        }; usedGPS.formUnion([kCGImagePropertyGPSAltitude as String, kCGImagePropertyGPSAltitudeRef as String])
        for key in gps.keys.sorted() where !usedGPS.contains(key) { append(key, display(gps[key]), to: &location) }
        func remaining(_ title: String, _ values: [String: Any], _ used: Set<String>) -> ImageMetadataSection? {
            let fields = values.keys.sorted().filter { !used.contains($0) }.compactMap { key -> ImageMetadataField? in
                guard let value = display(values[key]), !value.isEmpty else { return nil }; return ImageMetadataField(name: key, value: value)
            }
            return fields.isEmpty ? nil : ImageMetadataSection(title: title, fields: fields)
        }
        let additional = [remaining("Additional EXIF", exif, usedExif), remaining("Lens / Auxiliary", aux, usedAux), remaining("TIFF", tiff, usedTIFF)].compactMap { $0 }
        return ImageMetadata(imageFields: image, exifFields: camera, gpsFields: location, additional: additional, hasExif: !Set(exif.keys).subtracting(basicExif).isEmpty || !aux.isEmpty || !gps.isEmpty || !camera.isEmpty)
    }
    private static func exposure(_ seconds: Double) -> String {
        let reciprocal = 1 / seconds
        if seconds < 0.1, reciprocal.isFinite { return "1/" + decimal(reciprocal.rounded()) + " s" }
        return decimal(seconds, digits: 6) + " s"
    }
    private static func number(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue
        return number?.isFinite == true ? number : nil
    }
    private static func decimal(_ number: Double, digits: Int = 4) -> String {
        number.formatted(.number.grouping(.never).precision(.fractionLength(0...digits)))
    }
    private static func display(_ value: Any?, depth: Int = 0) -> String? {
        guard let value, depth < 4 else { return nil }
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? decimal(number.doubleValue) : nil }
        if let data = value as? Data { return "Binary metadata (\(data.count) bytes)" }
        if let array = value as? [Any] { return array.prefix(32).compactMap { display($0, depth: depth + 1) }.joined(separator: ", ") + (array.count > 32 ? " …" : "") }
        if let dictionary = value as? [String: Any] { return dictionary.keys.sorted().compactMap { key in display(dictionary[key], depth: depth + 1).map { key + ": " + $0 } }.joined(separator: "; ") }
        return nil
    }
}
