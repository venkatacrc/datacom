import Foundation

/// library.json, written by tools/build_library.py. The Mac app gets the full library,
/// including private decks the public web build leaves out.
struct Library: Decodable {
    var title: String
    var subtitle: String
    var built: String
    var version: String
    var tracks: [Track]
    var lessons: [Lesson]
    var cards: [Card]
    var problems: [Problem]
    var playground: [Template]
    var helpers: String

    static let empty = Library(title: "Datacom", subtitle: "", built: "", version: "", tracks: [], lessons: [],
                               cards: [], problems: [], playground: [], helpers: "")
}

struct Track: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let blurb: String
    let color: String
    let sections: [TrackSection]
    let sources: [Source]
}

struct TrackSection: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
}

struct Source: Decodable, Hashable {
    let id: String
    let title: String
    let url: String
}

struct Lesson: Decodable, Identifiable, Hashable {
    let id: String
    let track: String
    let section: String
    let title: String
    let html: String
    let url: String
    let source: String
}

struct Card: Decodable, Identifiable, Hashable {
    let id: String
    let track: String
    let section: String
    let label: String
    let front: String
    let back: String
    let lesson: String
}

struct Problem: Decodable, Identifiable, Hashable {
    let id: String
    let track: String
    let section: String
    let title: String
    let difficulty: String
    let tags: [String]
    let source: String
    let leetcode: String
    let needs: [String]
    let prompt: String
    let starter: String
    let solution: String
    let tests: String
    let file: String

    /// The program that runs the user's code and then the tests, as tools/check_problems.py does.
    func harness(_ code: String) -> String {
        let tests = (try? JSONEncoder().encode(self.tests)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let body = code.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return "\(body)\n\n\nimport dc as _dc\n_dc.run_tests(\(tests), globals())\n"
    }
}

struct Template: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let code: String
}

// ---- progress: the same JSON as the web app's export, so either app can import the other's file ----

struct Attempt: Codable, Hashable {
    var passed: Int
    var total: Int
    var at: Double
}

struct Solved: Codable, Hashable {
    var at: Double
}

struct Snippet: Codable, Hashable {
    var title: String
    var code: String
    var at: Double
}

struct StudyState: Codable {
    var cards: [String: String] = [:]
    var read: [String: Double] = [:]
    var solved: [String: Solved] = [:]
    var attempts: [String: Attempt] = [:]
    var code: [String: String] = [:]
    var snippets: [String: Snippet] = [:]
    var scratch: String?
    var stdin: String = ""
    /// Track ids included in Cards; nil means every track.
    var selected: [String]?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cards = (try? c.decodeIfPresent([String: String].self, forKey: .cards)) ?? [:]
        read = (try? c.decodeIfPresent([String: Double].self, forKey: .read)) ?? [:]
        solved = (try? c.decodeIfPresent([String: Solved].self, forKey: .solved)) ?? [:]
        attempts = (try? c.decodeIfPresent([String: Attempt].self, forKey: .attempts)) ?? [:]
        code = (try? c.decodeIfPresent([String: String].self, forKey: .code)) ?? [:]
        snippets = (try? c.decodeIfPresent([String: Snippet].self, forKey: .snippets)) ?? [:]
        scratch = try? c.decodeIfPresent(String.self, forKey: .scratch)
        stdin = (try? c.decodeIfPresent(String.self, forKey: .stdin)) ?? ""
        selected = try? c.decodeIfPresent([String].self, forKey: .selected)
    }
}

struct ProgressFile: Codable {
    var app = "datacom"
    var version = 1
    var exported: String?
    var state: StudyState
}

func now() -> Double { Date().timeIntervalSince1970 * 1000 }

enum Mode: String, CaseIterable, Identifiable {
    case learn, cards, code, progress
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .learn: return "book"
        case .cards: return "rectangle.on.rectangle.angled"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .progress: return "chart.bar"
        }
    }
}

enum CardMode: String, CaseIterable, Identifiable {
    case learn, test
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CardFilter: String, CaseIterable, Identifiable {
    case all, unknown, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All cards"
        case .unknown: return "Not yet known"
        case .review: return "Review only"
        }
    }
}
