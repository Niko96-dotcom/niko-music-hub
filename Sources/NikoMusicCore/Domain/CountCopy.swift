/// Count copy with the right singular/plural: "1 version", "2 versions".
///
/// Every count that reaches a person (UI, VoiceOver, status lines, logs, errors)
/// goes through here. It lives in NikoMusicCore so every module can reach it;
/// `CountCopySourceTests` fails on a raw `"\(count) songs"` or a hand-rolled
/// `== 1 ? "song" : "songs"` anywhere under Sources/.
public enum CountCopy {
    public static func count<Value: BinaryInteger>(_ value: Value, _ singular: String, plural: String? = nil) -> String {
        "\(value) \(noun(for: value, singular, plural: plural))"
    }

    public static func noun<Value: BinaryInteger>(for value: Value, _ singular: String, plural: String? = nil) -> String {
        value == 1 ? singular : (plural ?? singular + "s")
    }
}
