import Foundation

public enum Metadata {
    public static let version = 4
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
    private static let hits: Set<String> = ["Kick", "Snare", "Clap", "Hi-hat", "Percussion", "Impact"]
    static func labeledKind(_ text: String) -> String? {
        let words = tokens(text)
        if words.contains("oneshot") || words.contains("oneshots") || words.joined(separator: " ").contains("one shot") { return "One-shot" }
        if words.contains("loop") || words.contains("loops") { return "Loop" }
        return nil
    }
    /// Explicit labels win. Otherwise a named drum hit is a one-shot even when tempo-tagged,
    /// anything carrying a tempo is a loop, and untimed sounds (FX, foley, phrases) are
    /// one-shots, matching how Splice labels the same packs.
    public static func kind(name: String, folder: String) -> String {
        let components = [name] + folder.split(separator: "/").reversed().map(String.init)
        if let labeled = components.lazy.compactMap(labeledKind).first { return labeled }
        if hits.contains(category(name)) { return "One-shot" }
        if components.contains(where: { bpm($0) != nil }) { return "Loop" }
        return "One-shot"
    }
    public static func rootNote(_ name: String) -> String? {
        if let key = key(name) { return String(key.split(separator: " ")[0]) }
        let text = normalizedLabels(stem(name))
        // Delimited pitch tokens may appear before the tempo or sample description.
        // Bare notes in natural-language phrases ("A warm pad") are not root labels.
        let delimited = captures(#"(?:[_\[\](){},-])\s*([A-Ga-g](?:#|b)?)(?=$|[_\[\](){}\s-])"#, in: text)
        let terminal = captures(#"(?:^|\s)([A-G](?:#|b)?)(?:\s+\d{1,3})?$"#, in: text)
        let notes = Set((delimited + terminal).compactMap { note in normalizeKey(note + " major").map { String($0.split(separator: " ")[0]) } })
        return notes.count == 1 ? notes.first : nil
    }
    public static func bpm(_ name: String, kind: String = "Unknown") -> Double? {
        let text = normalizedLabels(stem(name))
        // Accept common tag separators and decimals without splitting 127.5 into 127.
        let patterns = [#"(?i)(?:^|[^a-z0-9.])(\d{2,3}(?:[.,]\d+)?)\s*[_:= -]*bpm(?:$|[^a-z])"#,
                        #"(?i)(?:^|[^a-z])bpm\s*[_:= -]*(\d{2,3}(?:[.,]\d+)?)(?=$|[^0-9.])"#,
                        // "(120, Gm)" pack convention: tempo then key inside one parenthesis.
                        #"\((\d{2,3}(?:[.,]\d+)?)\s*,\s*[A-Ga-g][#b]?(?:minor|major|min|maj|m)?\s*\)"#]
        let explicit = Set(patterns.flatMap { captures($0, in: text) }.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }.filter { (30...300).contains($0) })
        if !explicit.isEmpty { return explicit.count == 1 ? explicit.first : nil }
        // Bare tempo numbers are accepted only with loop context or a pitch label,
        // and only when there is one plausible candidate. Pack versions and hit IDs
        // remain ambiguous; audio-derived estimation is a separate future step.
        let effectiveKind = kind == "Unknown" ? (labeledKind(text) ?? "Unknown") : kind
        if effectiveKind != "One-shot" && (effectiveKind == "Loop" || key(text) != nil || rootNote(text) != nil) {
            let candidates = captures(#"(?:^|[_\[\](){}\s-])(\d{2,3}(?:[.,]\d+)?)(?=$|[_\[\](){}\s-])"#, in: text).compactMap { term -> Double? in
                guard !term.hasPrefix("0"), let value = Double(term.replacingOccurrences(of: ",", with: ".")), (50...240).contains(value) else { return nil }
                return value
            }
            if candidates.count == 1 { return candidates[0] }
        }
        return nil
    }
    public static func key(_ name: String) -> String? {
        let text = normalizedLabels(stem(name))
        let matches = captures(#"(?i)(?:^|[^a-z0-9])([a-g][#b]?[\s_.-]*(?:minor|major|min|maj|m))(?=$|[^a-z0-9])"#, in: text)
        let keys = Set(matches.compactMap(normalizeKey))
        return keys.count == 1 ? keys.first : nil
    }
    public static func normalizeKey(_ text: String) -> String? {
        let compact = normalizedLabels(text).components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "_.-"))).joined()
        let uppercaseMajor = compact.hasSuffix("M")
        let v = compact.lowercased()
        guard let match = capture(#"^([a-g][#b]?)(?:minor|major|min|maj|m)$"#, in: v) else { return nil }
        let aliases = ["cb":"B", "db":"C#", "eb":"D#", "fb":"E", "gb":"F#", "ab":"G#", "bb":"A#", "b#":"C", "e#":"F"]
        let note = aliases[match] ?? match.prefix(1).uppercased() + match.dropFirst()
        return note + ((uppercaseMajor || v.hasSuffix("major") || v.hasSuffix("maj")) ? " major" : " minor")
    }
    private static func stem(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        return ["wav", "wave", "aif", "aiff", "caf", "mp3", "m4a", "flac"].contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : name
    }
    private static func normalizedLabels(_ name: String) -> String {
        name.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: #"(?i)([a-g])[ _-]*sharp"#, with: "$1#", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)([a-g])[ _-]*flat"#, with: "$1b", options: .regularExpression)
    }
    private static let expressions = NSCache<NSString, NSRegularExpression>()
    private static func captures(_ pattern: String, in text: String) -> [String] {
        let re: NSRegularExpression
        if let cached = expressions.object(forKey: pattern as NSString) { re = cached }
        else {
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return [] }
            expressions.setObject(compiled, forKey: pattern as NSString); re = compiled
        }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
    static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text).first
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
