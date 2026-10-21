import Vision
import CoreVideo

enum VisionDetector {

    // (words Vision might use, what we say out loud)
    // person/dog/cat are handled by bounding-box detectors below so we can give directions.
    private static let known: [(words: [String], spoken: String)] = [
        (["chair"], "chair"),
        (["table", "desk"], "table"),
        (["door"], "door"),
        (["bottle"], "bottle"),
        (["cup", "mug"], "cup"),
        (["backpack"], "backpack"),
        (["laptop", "computer"], "laptop"),
        (["telephone", "phone", "smartphone", "mobile"], "phone"),
        (["car", "automobile"], "car"),
        (["bicycle", "bike"], "bicycle"),
        (["stairs", "staircase", "steps"], "staircase"),
        (["bed"], "bed"),
        (["couch", "sofa"], "couch"),
        (["television", "tv"], "TV"),
        (["book"], "book"),
        (["trash", "garbage", "waste"], "trash can")
    ]

    private static let tooGeneric: Set<String> = [
        "structure", "material", "indoor", "outdoor", "room", "wall", "floor", "ceiling",
        "furniture", "object", "item", "container", "plant", "fabric", "textile", "wood",
        "tool", "machine", "electronics", "light", "home", "building", "sky", "ground"
    ]

    // MARK: Describe surroundings
    static func describe(frame: CVPixelBuffer?, detailed: Bool, completion: @escaping (String) -> Void) {
        guard let frame = frame else {   // Simulator demo mode
            completion("I see a person on your left, and a chair.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let classify = VNClassifyImageRequest()
            let people = VNDetectHumanRectanglesRequest()
            let animals = VNRecognizeAnimalsRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .right)
            try? handler.perform([classify, people, animals])

            // Things with positions
            var positioned: [String] = []
            for p in (people.results ?? []).prefix(3) {
                positioned.append("a person " + place(p.boundingBox))
            }
            for a in (animals.results ?? []).prefix(2) {
                let name = a.labels.first?.identifier.lowercased() ?? "animal"
                positioned.append("a \(name) " + place(a.boundingBox))
            }

            // Things without positions (classifier)
            let limit = detailed ? 5 : 3
            let results = (classify.results ?? []).filter { $0.confidence > 0.2 }
            var found: [String] = []
            for obs in results {
                let words = obs.identifier.lowercased()
                    .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "," })
                    .map(String.init)
                for item in known where !found.contains(item.spoken) {
                    if item.words.contains(where: { words.contains($0) }) { found.append(item.spoken) }
                }
                if found.count >= limit { break }
            }
            if found.isEmpty && positioned.isEmpty,
               let best = results.first(where: { !tooGeneric.contains($0.identifier.lowercased()) }) {
                found = [best.identifier.replacingOccurrences(of: "_", with: " ")]
            }

            let parts = positioned + found.map(withArticle)
            let text = parts.isEmpty
                ? "I'm not sure what is in front of you. Try moving the camera."
                : "I see " + joined(parts) + "."
            DispatchQueue.main.async { completion(text) }
        }
    }

    // MARK: Read text (signs, menus, documents)
    static func readText(frame: CVPixelBuffer?, completion: @escaping (String) -> Void) {
        guard let frame = frame else {
            completion("Demo mode. No camera available to read text.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .right)
            try? handler.perform([request])

            // Top-to-bottom reading order (Vision's y origin is at the bottom)
            let lines = (request.results ?? [])
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }

            let text = lines.isEmpty
                ? "I couldn't find any text. Hold the camera steady and closer to the page."
                : lines.joined(separator: ". ")
            DispatchQueue.main.async { completion(text) }
        }
    }

    // MARK: Helpers
    private static func place(_ box: CGRect) -> String {
        let x = box.midX
        let side = x < 0.33 ? "on your left" : (x > 0.67 ? "on your right" : "ahead")
        return box.height > 0.6 ? side + ", close" : side
    }

    private static func withArticle(_ name: String) -> String {
        let vowel = "aeiou".contains(name.lowercased().first ?? "x")
        return (vowel ? "an " : "a ") + name
    }

    private static func joined(_ items: [String]) -> String {
        switch items.count {
        case 1: return items[0]
        case 2: return items[0] + " and " + items[1]
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
