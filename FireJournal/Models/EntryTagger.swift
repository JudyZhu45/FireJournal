//
//  EntryTagger.swift
//  FireJournal
//
//  Created by Codex on 4/26/26.
//

import Foundation
import UIKit
import Vision
import ImageIO

/// Generates tags for an entry from text and optional photo content.
struct EntryTagger {
    struct PhotoMetadata {
        let timestamp: Date?
        let longitude: Double?
        let latitude: Double?
    }

    /// Builds a de-duplicated tag list from caption + photo labels.
    func tags(for caption: String, photoData: Data?) -> [String] {
        var combined = hashtagTags(from: caption)
        combined.append(contentsOf: emojiTags(from: caption))

        if let photoData {
            print("EntryTagger: photo provided (\(photoData.count) bytes). Running Vision classification...")
            let photoTags = visionTags(from: photoData)
            combined.append(contentsOf: photoTags)
        } else {
            print("EntryTagger: no photo provided. Skipping Vision classification.")
        }

        return unique(combined)
    }

    /// Extracts timestamp and GPS metadata from raw photo bytes.
    func extractPhotoMetadata(from photoData: Data) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            print("EntryTagger: no image metadata found.")
            return PhotoMetadata(timestamp: nil, longitude: nil, latitude: nil)
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        let timestamp = parseExifDate(from: exif)
        let latitude = parseLatitude(from: gps)
        let longitude = parseLongitude(from: gps)

        if timestamp == nil, latitude == nil, longitude == nil {
            print("EntryTagger: metadata extraction ran, but no timestamp/GPS values were present.")
        } else {
            print("EntryTagger: extracted metadata timestamp=\(String(describing: timestamp)) latitude=\(String(describing: latitude)) longitude=\(String(describing: longitude))")
        }

        return PhotoMetadata(timestamp: timestamp, longitude: longitude, latitude: latitude)
    }

    /// Extracts hashtag tags like `#park` -> `park`.
    private func hashtagTags(from caption: String) -> [String] {
        let allowedTagCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        var parsedTags: [String] = []

        for token in caption.split(whereSeparator: \.isWhitespace) {
            let raw = String(token)
            guard raw.hasPrefix("#"), raw.count > 1 else { continue }

            let core = String(raw.dropFirst())
            let cleaned = core.unicodeScalars
                .filter { allowedTagCharacters.contains($0) }
                .map(String.init)
                .joined()
                .lowercased()

            if !cleaned.isEmpty {
                parsedTags.append(cleaned)
            }
        }

        return unique(parsedTags)
    }

    /// Returns emoji tags inferred from keyword matches in caption text.
    private func emojiTags(from caption: String) -> [String] {
        let words = caption
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let wordSet = Set(words)
        var tags: [String] = []

        for (emoji, keywords) in emojiKeywordMap {
            if keywords.contains(where: { wordSet.contains($0) }) {
                tags.append(emoji)
            }
        }

        return unique(tags)
    }

    /// Uses Vision classification to infer high-confidence photo tags.
    private func visionTags(from photoData: Data) -> [String] {
        #if targetEnvironment(simulator)
        print("EntryTagger: Vision/CoreML tagging disabled on Simulator.")
        return []
        #endif

        guard let uiImage = downsampledImageForVision(from: photoData),
              let cgImage = uiImage.cgImage else {
            print("EntryTagger: Vision skipped. Could not decode image data.")
            return []
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            let allResults = request.results ?? []
            if allResults.isEmpty {
                print("EntryTagger: Vision ran but found no classifications.")
            } else {
                print("Vision classifications (\(allResults.count)):")
                for observation in allResults {
                    let confidence = String(format: "%.3f", observation.confidence)
                    print("- \(observation.identifier) [\(confidence)]")
                }
            }

            let tags = allResults
                .filter { $0.confidence >= 0.75 }
                .prefix(5)
                .compactMap { observation in
                    normalizedVisionTag(from: observation.identifier)
                }
            if tags.isEmpty {
                print("EntryTagger: no high-confidence Vision tags (threshold: 0.75).")
            } else {
                print("EntryTagger: selected Vision tags -> \(tags)")
            }
            return unique(tags)
        } catch {
            print("EntryTagger: Vision request failed with error -> \(error.localizedDescription)")
            if error.localizedDescription.localizedCaseInsensitiveContains("espresso context") {
                #if targetEnvironment(simulator)
                print("EntryTagger: this often occurs on Simulator. Test Vision tagging on a physical iPhone/iPad.")
                #else
                print("EntryTagger: failed to initialize Vision/Core ML runtime. Try with a smaller image or restart the app/device.")
                #endif
            }
            return []
        }
    }

    /// Downsamples large photos so Vision classification is less memory-intensive.
    private func downsampledImageForVision(from photoData: Data, maxDimension: CGFloat = 1024) -> UIImage? {
        guard let image = UIImage(data: photoData) else { return nil }
        let size = image.size
        let largestDimension = max(size.width, size.height)
        guard largestDimension > maxDimension else { return image }

        let scale = maxDimension / largestDimension
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Normalizes a Vision identifier into a compact tag.
    private func normalizedVisionTag(from identifier: String) -> String? {
        let primary = identifier
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? identifier

        let cleaned = primary
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0) }
            .map(String.init)
            .joined()

        return cleaned.isEmpty ? nil : cleaned
    }

    private func unique(_ tags: [String]) -> [String] {
        Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }

    private func parseExifDate(from exif: [CFString: Any]?) -> Date? {
        guard let exif else { return nil }
        let dateString = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)

        guard let dateString else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }

    private func parseLatitude(from gps: [CFString: Any]?) -> Double? {
        guard let gps,
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double else { return nil }
        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        return latitudeRef == "S" ? -latitude : latitude
    }

    private func parseLongitude(from gps: [CFString: Any]?) -> Double? {
        guard let gps,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
        return longitudeRef == "W" ? -longitude : longitude
    }

    /// Local keyword-to-emoji map.
    /// Includes general moods/topics plus sports-focused tags.
    private var emojiKeywordMap: [(String, [String])] {
        [
            ("😄", ["happy", "great", "awesome", "fun", "joy"]),
            ("😢", ["sad", "upset", "cry", "down"]),
            ("🔥", ["fire", "hot", "burn", "lit"]),
            ("💼", ["work", "office", "meeting", "job"]),
            ("📚", ["study", "class", "homework", "read", "exam"]),
            ("🍔", ["food", "lunch", "dinner", "breakfast", "eat", "meal"]),
            ("☕️", ["coffee", "cafe", "espresso"]),
            ("🎵", ["music", "song", "concert", "band"]),
            ("✈️", ["travel", "flight", "airport", "trip", "vacation"]),
            ("🏃", ["run", "running", "jog", "workout", "exercise"]),
            ("💪", ["gym", "lift", "training", "fitness"]),
            ("⚽️", ["soccer", "football"]),
            ("🏀", ["basketball", "nba", "hoops"]),
            ("🏈", ["nfl", "touchdown", "quarterback", "football"]),
            ("⚾️", ["baseball", "mlb", "pitch", "homerun", "home run"]),
            ("🎾", ["tennis", "racket", "match"]),
            ("🏐", ["volleyball", "serve", "spike"]),
            ("🏒", ["hockey", "nhl", "puck"]),
            ("🏌️", ["golf", "putt", "tee", "fairway"]),
            ("🥊", ["boxing", "box", "spar", "fight"]),
            ("🏊", ["swim", "swimming", "pool", "laps"]),
            ("🚴", ["bike", "biking", "cycling", "ride"])
        ]
    }
}
