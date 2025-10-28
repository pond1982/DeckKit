import Foundation
import SwiftUI

struct SplitRailCharactersFile: Decodable {
    let version: String
    let generatedAt: String
    let characters: [SplitRailCharacter]
}

struct SplitRailCharacter: Decodable, Identifiable {
    let id: String
    let label: String
    let role: String
    let ageBand: String
    let groupSize: Int
    let legalStatus: String
    let vulnerability: String
    let dependents: Int
    let relationship: String
    let futureImpactMu: Double
    let futureImpactSigma: Double
    let certaintyBase: Double
    let lensTags: [String]
    let optOutSensitive: Bool
}

enum SplitRailLoader {

    static func loadCharacters() -> [SplitRailCharacter] {
        guard let url = Bundle.main.url(forResource: "split_rail_characters_v1", withExtension: "json") else {
            #if DEBUG
            print("split_rail_characters_v1.json not found in bundle")
            #endif
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(SplitRailCharactersFile.self, from: data)
            return decoded.characters
        } catch {
            #if DEBUG
            print("Failed to decode split_rail_characters_v1.json: \(error)")
            #endif
            return []
        }
    }
}

extension SplitRailCharacter {

    // Map a character into a Hobby card, using requested fields.
    // - Title: "role + ageBand"
    // - Text: legalStatus, vulnerability, relationship
    func asHobby(number: Int) -> Hobby {
        let title = "\(role.capitalized) • \(ageBand.capitalized)"
        let body = "Status: \(legalStatus.replacingOccurrences(of: "_", with: " "))\nVulnerability: \(vulnerability.replacingOccurrences(of: "_", with: " "))\nRelationship: \(relationship.replacingOccurrences(of: "_", with: " "))"
        // Pick a deterministic color and symbol based on id hash
        let colors: [Color] = [.green, .blue, .yellow, .red, .orange, .brown, .purple, .pink, .teal, .indigo]
        let symbols: [String] = [
            "person", "figure.walk", "figure.wave", "star", "bolt", "globe", "heart", "leaf", "briefcase", "graduationcap"
        ]
        let idx = abs(id.hashValue)
        let color = colors[idx % colors.count]
        let image = symbols[idx % symbols.count]
        return Hobby(number: number, name: title, color: color, text: body, imageName: image)
    }
}
