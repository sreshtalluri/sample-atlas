import Foundation

public enum Metadata {
    public static let version = 2
    public static let categories = ["Riser", "Sweep", "Downlifter", "Impact", "Kick", "Snare", "Clap", "Hi-hat", "Percussion", "Drums", "Bass", "Vocal", "Pad", "Synth", "Piano", "Guitar", "FX", "Other"]
    public static let synonyms: [String: [String]] = [
        "riser": ["riser", "risers", "uplifter", "uplifters", "rise"],
        "sweep": ["sweep", "sweeps", "whoosh", "whooshes", "swoosh"],
        "downlifter": ["downlifter", "downlifters", "downer", "downers"],
        "impact": ["impact", "impacts", "hit", "boom"],
        "kick": ["kick", "kicks", "bd"], "snare": ["snare", "snares", "sd"], "clap": ["clap", "claps"],
        "hihat": ["hihat", "hat", "hats", "hh"], "percussion": ["percussion", "perc", "conga", "shaker"],
        "drums": ["drums", "drum", "break", "breakbeat"], "bass": ["bass", "sub", "808"],
        "vocal": ["vocal", "vocals", "vox", "voice"], "pad": ["pad", "pads", "atmosphere", "ambient"],
        "synth": ["synth", "lead", "arp", "pluck"], "piano": ["piano", "keys", "keyboard"],
        "guitar": ["guitar", "gtr"], "fx": ["fx", "effect", "effects", "noise", "transition"]
    ]
    public static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    public static func category(_ text: String) -> String {
        let words = Set(tokens(text))
        return categories.first { name in
            let key = name.lowercased().replacingOccurrences(of: "-", with: "")
            return !(words.intersection(synonyms[key] ?? [])).isEmpty
        } ?? "Other"
    }
    public static func category(name: String, folder: String) -> String {
        let named = category(name)
        if !["Other", "Drums", "FX"].contains(named) { return named }
        for component in folder.split(separator: "/").reversed() {
            let candidate = category(String(component))
            if candidate != "Other" { return candidate }
        }
        return named
    }
    public static func kind(name: String, folder: String) -> String {
        for component in [name] + folder.split(separator: "/").reversed().map(String.init) {
            let words = tokens(component)
            if words.contains("oneshot") || words.contains("oneshots") || words.joined(separator: " ").contains("one shot") { return "One-shot" }
            if words.contains("loop") || words.contains("loops") { return "Loop" }
        }
        return "Unknown"
    }
    public static func rootNote(_ name: String) -> String? {
        if let key = key(name) { return String(key.split(separator: " ")[0]) }
        // A final pitch label is a root note, not evidence of a major/minor key.
        guard let note = capture(#"(?:[_ -])([A-G](?:#|b|♯|♭)?)(?:[_ -]\d{1,3})?$"#, in: name),
              let key = normalizeKey(note + " major") else { return nil }
        return String(key.split(separator: " ")[0])
    }
    public static func bpm(_ name: String, kind: String = "Unknown") -> Double? {
        // Require an explicit BPM marker: pack numbers and 808 are not tempos.
        let patterns = [#"(?i)(?:^|[^a-z0-9])(\d{2,3}(?:\.\d+)?)\s*[-_ ]?bpm(?:$|[^a-z])"#,
                        #"(?i)(?:^|[^a-z])bpm\s*[-_ ]?(\d{2,3}(?:\.\d+)?)(?:$|[^0-9])"#]
        for pattern in patterns {
            if let value = capture(pattern, in: name), let number = Double(value), (30...300).contains(number) { return number }
        }
        // Bare tempo numbers are accepted only with loop context or a pitch label,
        // and only when there is one plausible candidate. Pack versions and hit IDs
        // remain ambiguous; audio-derived estimation is a separate future step.
        if kind != "One-shot" && (kind == "Loop" || key(name) != nil || rootNote(name) != nil) {
            let candidates = tokens(name).compactMap { term -> Double? in
                guard term.count >= 2, !term.hasPrefix("0"), let value = Double(term), (50...240).contains(value) else { return nil }
                return value
            }
            if candidates.count == 1 { return candidates[0] }
        }
        return nil
    }
    public static func key(_ name: String) -> String? {
        guard let value = capture(#"(?i)(?:^|[^a-z0-9])([a-g][#b♯♭]?[ _-]?(?:minor|major|min|maj|m))(?=$|[^a-z0-9])"#, in: name) else { return nil }
        return normalizeKey(value)
    }
    public static func normalizeKey(_ text: String) -> String? {
        let v = text.lowercased().replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        guard let match = capture(#"^([a-g][#b]?)(?:minor|major|min|maj|m)$"#, in: v) else { return nil }
        let aliases = ["cb":"B", "db":"C#", "eb":"D#", "fb":"E", "gb":"F#", "ab":"G#", "bb":"A#", "b#":"C", "e#":"F"]
        let note = aliases[match] ?? match.prefix(1).uppercased() + match.dropFirst()
        return note + ((v.hasSuffix("major") || v.hasSuffix("maj")) ? " major" : " minor")
    }
    static func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
    public static func ftsQuery(_ text: String) -> String? {
        let terms = Array(tokens(text).prefix(24))
        guard !terms.isEmpty else { return nil }
        return terms.map { term in
            let alternatives = synonyms.values.first(where: { $0.contains(term) }) ?? [term]
            return "(" + alternatives.map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"
        }.joined(separator: " AND ")
    }
}
