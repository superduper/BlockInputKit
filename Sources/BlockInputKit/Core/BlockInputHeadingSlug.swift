/// Generates a GitHub-style anchor slug from a heading's title: lowercase, spaces to hyphens,
/// characters outside [a-z0-9-] removed, repeated/edge hyphens collapsed.
public enum BlockInputHeadingSlug {
    public static func make(_ title: String) -> String {
        var slug = ""
        var pendingDash = false
        for scalar in title.lowercased().unicodeScalars {
            if scalar == " " || scalar == "-" || scalar == "_" {
                pendingDash = !slug.isEmpty
                continue
            }
            let isAllowed = (scalar.value >= 97 && scalar.value <= 122) // a-z
                || (scalar.value >= 48 && scalar.value <= 57)          // 0-9
            if isAllowed {
                if pendingDash { slug.append("-"); pendingDash = false }
                slug.unicodeScalars.append(scalar)
            }
        }
        return slug
    }
}
