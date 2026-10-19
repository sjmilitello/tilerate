import Foundation

/// The tile picker's colours (owner, 2026-10-18).
enum TilePalette {
    /// Tile colours: nine families, each in even light-to-dark steps,
    /// measured from 1,045 TileBar tiles (their 12 single-colour groups, each
    /// product's own colour where it matched its group; purple left out — one
    /// in 34 was). Real tile is muted: a few stronger greens, blues and reds.
    static let families: [(name: String, colours: [String])] = [
        ("Whites", ["#FAFAFA", "#F0F4F8", "#F7F3EB", "#F4ECDB", "#E6E4E0"]),
        ("Grays", ["#CDCAC6", "#AFABA5", "#938D86", "#76706C", "#5A5450", "#3D3B3B", "#252322", "#0E0D0D"]),
        ("Beige", ["#E6DCD0", "#D3C9BC", "#C3B5A5", "#B5A18C", "#A68D76"]),
        ("Brown", ["#A5856B", "#8B6C56", "#705443", "#533F34", "#3B2920"]),
        ("Terracotta", ["#E5BA9A", "#CF9F7F", "#BB8465", "#A36A51", "#8F5039"]),
        ("Red & pink", ["#F0CFC7", "#D1AEA6", "#BD8A7F", "#DC4131", "#AA2015", "#76070B"]),
        ("Yellow", ["#F1E5B8", "#E8CF83", "#DBB155", "#BD8F41", "#956B33"]),
        ("Green", ["#B9DAC9", "#89B19E", "#658679", "#445D4F", "#203B17", "#4B9779", "#225A39"]),
        ("Blue", ["#B6D6ED", "#83A8B8", "#5D798B", "#304D66", "#032641", "#1988A3", "#286CAB"]),
    ]

    /// Laticrete PermaColor grout (owner's grout, 2026-10-18): its 40
    /// colours with Laticrete's names and on-screen swatch values, in six
    /// families. On screen they're a guide; grout dries to its own shade.
    static let grouts: [(name: String, colours: [(name: String, hex: String)])] = [
        ("Whites", [("Bright White", "#FFFEF4"), ("Silk", "#F1DBC2"), ("Sauterne", "#E7DACB"), ("Almond", "#E5D4C0"), ("Antique White", "#D6C2AC"), ("Mushroom", "#CFB9A3"), ("Marble Beige", "#C9B6A7")]),
        ("Beige", [("Walnut", "#BEAF9D"), ("Butter Cream", "#C8AC91"), ("Toasted Almond", "#BF9E7F"), ("Latte", "#B8A392"), ("Parchment", "#B79D87"), ("Hemp", "#A29185"), ("Sand Beige", "#A38976"), ("Desert Khaki", "#9E8773")]),
        ("Brown", [("Hot Cocoa", "#8E7B70"), ("Terra Cotta", "#8E6858"), ("Autumn Green", "#7A6D5C"), ("Quarry Red", "#76544E"), ("Chestnut Brown", "#6F5C52"), ("Mocha", "#645B55"), ("Espresso", "#5E4E49")]),
        ("Light gray", [("Frosty", "#CFCBC5"), ("Mink", "#CBC6BD"), ("Silver Shadow", "#C9C6C4"), ("Steamship", "#BDBFBE"), ("Fossil", "#C9BFB4"), ("Light Pewter", "#C8C0B4"), ("Iron", "#BAB4AA")]),
        ("Gray", [("Smoke Grey", "#B2AEAA"), ("Stormy Grey", "#A5A19A"), ("Sterling Silver", "#A09893"), ("Natural Grey", "#908A7F"), ("Sandstone", "#7D7371"), ("Dusty Grey", "#686460")]),
        ("Dark & blue", [("Slate Grey", "#78858C"), ("Twilight Blue", "#586C75"), ("Platinum", "#6C7274"), ("Raven", "#595A5D"), ("Midnight Black", "#3A3D3E")]),
    ]

    static let groutMaker = "PermaColor"

    /// Shorter family names, so every family fits across.
    static func shortName(_ name: String) -> String {
        switch name {
        case "Terracotta": "Terra"
        case "Red & pink": "Red"
        case "Dark & blue": "Dark"
        case "Light gray": "Light"
        default: name
        }
    }
}
