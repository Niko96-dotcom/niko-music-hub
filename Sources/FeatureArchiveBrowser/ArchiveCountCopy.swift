/// Count copy with the right singular/plural: "1 version", "2 versions".
enum ArchiveCountCopy {
    static func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        "\(value) \(noun(for: value, singular, plural: plural))"
    }

    static func noun(for value: Int, _ singular: String, plural: String? = nil) -> String {
        value == 1 ? singular : (plural ?? singular + "s")
    }
}
