//  BookNameMapper.swift
//  BibleApp
//
//  Maps English book names (as returned by Lectio API) to:
//    • Indonesian display name
//    • Local database slug (used as file/key name)
//    • Indonesian intro rubric
//    • ReadingType (.gospel vs others)
//    • Whether it's a Deuterocanonical book

import Foundation

// MARK: - BookInfo

struct BookInfo {
    let englishName: String
    let indonesianName: String
    let slug: String                      // key in BibleDatabase
    let introRubric: String               // "Bacaan dari …"
    let isGospel: Bool
    let isDeuterocanonical: Bool
}

// MARK: - BookNameMapper

enum BookNameMapper {

    // MARK: Lookup

    /// Returns info for an English book name, case-insensitive.
    /// Also handles common abbreviations (e.g. "1 Cor", "Ps", "Sir").
    static func info(forEnglish raw: String) -> BookInfo? {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return byEnglish[key]
    }

    /// Maps a Lectio API reading-type string to our `ReadingType` enum.
    static func readingType(from lectionaryType: String) -> ReadingType {
        switch lectionaryType.lowercased() {
        case "first_reading", "first reading", "reading_1":
            return .firstReading
        case "second_reading", "second reading", "reading_2":
            return .secondReading
        case "responsorial_psalm", "psalm", "responsorialpsalm":
            return .psalm
        case "gospel":
            return .gospel
        case "alleluia", "gospel_acclamation", "gospel acclamation":
            return .alleluia
        default:
            return .firstReading
        }
    }

    /// Maps a Lectio API season string to our `LiturgicalSeason` enum.
    static func season(from raw: String) -> LiturgicalSeason {
        switch raw.lowercased() {
        case "advent":                  return .advent
        case "christmas", "xmas":       return .christmas
        case "lent":                    return .lent
        case "easter", "eastertide":    return .easter
        case "ordinary", "ordinarytime",
             "ordinary time":           return .ordinaryTime
        default:                        return .feastDay
        }
    }

    // MARK: - Full mapping table (73 Catholic books)
    // Keys are lowercase; multiple aliases per book are supported.

    // swiftlint:disable line_length
    private static let byEnglish: [String: BookInfo] = {
        var map: [String: BookInfo] = [:]

        func add(_ info: BookInfo, aliases: [String] = []) {
            let keys = ([info.englishName.lowercased()] + aliases.map { $0.lowercased() })
            keys.forEach { map[$0] = info }
        }

        // ── Old Testament ────────────────────────────────────────────────

        add(.init(englishName: "Genesis",        indonesianName: "Kejadian",             slug: "kej",  introRubric: "Bacaan dari Kitab Kejadian.",              isGospel: false, isDeuterocanonical: false), aliases: ["gen", "ge", "gn"])
        add(.init(englishName: "Exodus",         indonesianName: "Keluaran",             slug: "kel",  introRubric: "Bacaan dari Kitab Keluaran.",               isGospel: false, isDeuterocanonical: false), aliases: ["exod", "ex"])
        add(.init(englishName: "Leviticus",      indonesianName: "Imamat",               slug: "ima",  introRubric: "Bacaan dari Kitab Imamat.",                 isGospel: false, isDeuterocanonical: false), aliases: ["lev", "lv"])
        add(.init(englishName: "Numbers",        indonesianName: "Bilangan",             slug: "bil",  introRubric: "Bacaan dari Kitab Bilangan.",               isGospel: false, isDeuterocanonical: false), aliases: ["num", "nm"])
        add(.init(englishName: "Deuteronomy",    indonesianName: "Ulangan",              slug: "ul",   introRubric: "Bacaan dari Kitab Ulangan.",                isGospel: false, isDeuterocanonical: false), aliases: ["deut", "dt"])
        add(.init(englishName: "Joshua",         indonesianName: "Yosua",                slug: "yos",  introRubric: "Bacaan dari Kitab Yosua.",                  isGospel: false, isDeuterocanonical: false), aliases: ["josh"])
        add(.init(englishName: "Judges",         indonesianName: "Hakim-Hakim",          slug: "hak",  introRubric: "Bacaan dari Kitab Hakim-Hakim.",            isGospel: false, isDeuterocanonical: false), aliases: ["judg"])
        add(.init(englishName: "Ruth",           indonesianName: "Rut",                  slug: "rut",  introRubric: "Bacaan dari Kitab Rut.",                    isGospel: false, isDeuterocanonical: false), aliases: ["ru"])
        add(.init(englishName: "1 Samuel",       indonesianName: "1 Samuel",             slug: "1sam", introRubric: "Bacaan dari Kitab Samuel yang Pertama.",    isGospel: false, isDeuterocanonical: false), aliases: ["1sam", "1 sam"])
        add(.init(englishName: "2 Samuel",       indonesianName: "2 Samuel",             slug: "2sam", introRubric: "Bacaan dari Kitab Samuel yang Kedua.",      isGospel: false, isDeuterocanonical: false), aliases: ["2sam", "2 sam"])
        add(.init(englishName: "1 Kings",        indonesianName: "1 Raja-Raja",          slug: "1raj", introRubric: "Bacaan dari Kitab Raja-Raja yang Pertama.", isGospel: false, isDeuterocanonical: false), aliases: ["1kgs", "1 kgs", "1 kings"])
        add(.init(englishName: "2 Kings",        indonesianName: "2 Raja-Raja",          slug: "2raj", introRubric: "Bacaan dari Kitab Raja-Raja yang Kedua.",   isGospel: false, isDeuterocanonical: false), aliases: ["2kgs", "2 kgs", "2 kings"])
        add(.init(englishName: "1 Chronicles",   indonesianName: "1 Tawarikh",           slug: "1taw", introRubric: "Bacaan dari Kitab Tawarikh yang Pertama.",  isGospel: false, isDeuterocanonical: false), aliases: ["1chr", "1 chr"])
        add(.init(englishName: "2 Chronicles",   indonesianName: "2 Tawarikh",           slug: "2taw", introRubric: "Bacaan dari Kitab Tawarikh yang Kedua.",    isGospel: false, isDeuterocanonical: false), aliases: ["2chr", "2 chr"])
        add(.init(englishName: "Ezra",           indonesianName: "Ezra",                 slug: "ezr",  introRubric: "Bacaan dari Kitab Ezra.",                   isGospel: false, isDeuterocanonical: false), aliases: ["ez"])
        add(.init(englishName: "Nehemiah",       indonesianName: "Nehemia",              slug: "neh",  introRubric: "Bacaan dari Kitab Nehemia.",                isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Esther",         indonesianName: "Ester",                slug: "est",  introRubric: "Bacaan dari Kitab Ester.",                  isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Job",            indonesianName: "Ayub",                 slug: "ayb",  introRubric: "Bacaan dari Kitab Ayub.",                   isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Psalms",         indonesianName: "Mazmur",               slug: "mzm",  introRubric: "Mazmur Tanggapan.",                         isGospel: false, isDeuterocanonical: false), aliases: ["psalm", "ps", "psa", "pss"])
        add(.init(englishName: "Proverbs",       indonesianName: "Amsal",                slug: "ams",  introRubric: "Bacaan dari Kitab Amsal.",                  isGospel: false, isDeuterocanonical: false), aliases: ["prov", "pr"])
        add(.init(englishName: "Ecclesiastes",   indonesianName: "Pengkhotbah",          slug: "pkh",  introRubric: "Bacaan dari Kitab Pengkhotbah.",            isGospel: false, isDeuterocanonical: false), aliases: ["eccl", "qoh", "qoheleth"])
        add(.init(englishName: "Song of Solomon",indonesianName: "Kidung Agung",         slug: "kid",  introRubric: "Bacaan dari Kidung Agung.",                 isGospel: false, isDeuterocanonical: false), aliases: ["song", "sos", "song of songs", "canticles"])
        add(.init(englishName: "Isaiah",         indonesianName: "Yesaya",               slug: "yes",  introRubric: "Bacaan dari Kitab Yesaya.",                 isGospel: false, isDeuterocanonical: false), aliases: ["isa"])
        add(.init(englishName: "Jeremiah",       indonesianName: "Yeremia",              slug: "yer",  introRubric: "Bacaan dari Kitab Yeremia.",                isGospel: false, isDeuterocanonical: false), aliases: ["jer"])
        add(.init(englishName: "Lamentations",   indonesianName: "Ratapan",              slug: "rat",  introRubric: "Bacaan dari Kitab Ratapan.",                isGospel: false, isDeuterocanonical: false), aliases: ["lam"])
        add(.init(englishName: "Ezekiel",        indonesianName: "Yehezkiel",            slug: "yeh",  introRubric: "Bacaan dari Kitab Yehezkiel.",              isGospel: false, isDeuterocanonical: false), aliases: ["ezek"])
        add(.init(englishName: "Daniel",         indonesianName: "Daniel",               slug: "dan",  introRubric: "Bacaan dari Kitab Daniel.",                 isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Hosea",          indonesianName: "Hosea",                slug: "hos",  introRubric: "Bacaan dari Kitab Hosea.",                  isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Joel",           indonesianName: "Yoel",                 slug: "yol",  introRubric: "Bacaan dari Kitab Yoel.",                   isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Amos",           indonesianName: "Amos",                 slug: "amo",  introRubric: "Bacaan dari Kitab Amos.",                   isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Obadiah",        indonesianName: "Obaja",                slug: "oba",  introRubric: "Bacaan dari Kitab Obaja.",                  isGospel: false, isDeuterocanonical: false), aliases: ["obad"])
        add(.init(englishName: "Jonah",          indonesianName: "Yunus",                slug: "yun",  introRubric: "Bacaan dari Kitab Yunus.",                  isGospel: false, isDeuterocanonical: false), aliases: ["jon"])
        add(.init(englishName: "Micah",          indonesianName: "Mikha",                slug: "mik",  introRubric: "Bacaan dari Kitab Mikha.",                  isGospel: false, isDeuterocanonical: false), aliases: ["mic"])
        add(.init(englishName: "Nahum",          indonesianName: "Nahum",                slug: "nah",  introRubric: "Bacaan dari Kitab Nahum.",                  isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Habakkuk",       indonesianName: "Habakuk",              slug: "hab",  introRubric: "Bacaan dari Kitab Habakuk.",                isGospel: false, isDeuterocanonical: false), aliases: ["hab"])
        add(.init(englishName: "Zephaniah",      indonesianName: "Zefanya",              slug: "zef",  introRubric: "Bacaan dari Kitab Zefanya.",                isGospel: false, isDeuterocanonical: false), aliases: ["zeph"])
        add(.init(englishName: "Haggai",         indonesianName: "Hagai",                slug: "hag",  introRubric: "Bacaan dari Kitab Hagai.",                  isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Zechariah",      indonesianName: "Zakharia",             slug: "zak",  introRubric: "Bacaan dari Kitab Zakharia.",               isGospel: false, isDeuterocanonical: false), aliases: ["zech"])
        add(.init(englishName: "Malachi",        indonesianName: "Maleakhi",             slug: "mal",  introRubric: "Bacaan dari Kitab Maleakhi.",               isGospel: false, isDeuterocanonical: false))

        // ── Deuterocanonical (Catholic only) ────────────────────────────

        add(.init(englishName: "Tobit",          indonesianName: "Tobit",                slug: "tob",  introRubric: "Bacaan dari Kitab Tobit.",                  isGospel: false, isDeuterocanonical: true), aliases: ["tob"])
        add(.init(englishName: "Judith",         indonesianName: "Yudit",                slug: "ydt",  introRubric: "Bacaan dari Kitab Yudit.",                  isGospel: false, isDeuterocanonical: true), aliases: ["jdt"])
        add(.init(englishName: "1 Maccabees",    indonesianName: "1 Makabe",             slug: "1mak", introRubric: "Bacaan dari Kitab Makabe yang Pertama.",    isGospel: false, isDeuterocanonical: true), aliases: ["1 macc", "1macc", "1mac"])
        add(.init(englishName: "2 Maccabees",    indonesianName: "2 Makabe",             slug: "2mak", introRubric: "Bacaan dari Kitab Makabe yang Kedua.",      isGospel: false, isDeuterocanonical: true), aliases: ["2 macc", "2macc", "2mac"])
        add(.init(englishName: "Wisdom",         indonesianName: "Kebijaksanaan",        slug: "keb",  introRubric: "Bacaan dari Kitab Kebijaksanaan.",          isGospel: false, isDeuterocanonical: true), aliases: ["wis", "wisdom of solomon"])
        add(.init(englishName: "Sirach",         indonesianName: "Sirakh",               slug: "sir",  introRubric: "Bacaan dari Kitab Sirakh.",                 isGospel: false, isDeuterocanonical: true), aliases: ["sir", "ecclesiasticus", "ecclus"])
        add(.init(englishName: "Baruch",         indonesianName: "Barukh",               slug: "bar",  introRubric: "Bacaan dari Kitab Barukh.",                 isGospel: false, isDeuterocanonical: true))

        // ── New Testament ────────────────────────────────────────────────

        add(.init(englishName: "Matthew",        indonesianName: "Matius",               slug: "mat",  introRubric: "Inilah Injil Yesus Kristus menurut Matius.", isGospel: true, isDeuterocanonical: false), aliases: ["matt", "mt"])
        add(.init(englishName: "Mark",           indonesianName: "Markus",               slug: "mrk",  introRubric: "Inilah Injil Yesus Kristus menurut Markus.", isGospel: true, isDeuterocanonical: false), aliases: ["mk"])
        add(.init(englishName: "Luke",           indonesianName: "Lukas",                slug: "luk",  introRubric: "Inilah Injil Yesus Kristus menurut Lukas.",  isGospel: true, isDeuterocanonical: false), aliases: ["lk"])
        add(.init(englishName: "John",           indonesianName: "Yohanes",              slug: "yoh",  introRubric: "Inilah Injil Yesus Kristus menurut Yohanes.",isGospel: true, isDeuterocanonical: false), aliases: ["jn"])
        add(.init(englishName: "Acts",           indonesianName: "Kisah Para Rasul",     slug: "kis",  introRubric: "Bacaan dari Kisah Para Rasul.",              isGospel: false, isDeuterocanonical: false), aliases: ["acts of the apostles", "ac"])
        add(.init(englishName: "Romans",         indonesianName: "Roma",                 slug: "rom",  introRubric: "Bacaan dari Surat Rasul Paulus kepada Jemaat di Roma.", isGospel: false, isDeuterocanonical: false), aliases: ["rom", "ro"])
        add(.init(englishName: "1 Corinthians",  indonesianName: "1 Korintus",           slug: "1kor", introRubric: "Bacaan dari Surat Pertama Rasul Paulus kepada Jemaat di Korintus.", isGospel: false, isDeuterocanonical: false), aliases: ["1 cor", "1cor"])
        add(.init(englishName: "2 Corinthians",  indonesianName: "2 Korintus",           slug: "2kor", introRubric: "Bacaan dari Surat Kedua Rasul Paulus kepada Jemaat di Korintus.",  isGospel: false, isDeuterocanonical: false), aliases: ["2 cor", "2cor"])
        add(.init(englishName: "Galatians",      indonesianName: "Galatia",              slug: "gal",  introRubric: "Bacaan dari Surat Rasul Paulus kepada Jemaat di Galatia.",         isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Ephesians",      indonesianName: "Efesus",               slug: "ef",   introRubric: "Bacaan dari Surat Rasul Paulus kepada Jemaat di Efesus.",           isGospel: false, isDeuterocanonical: false), aliases: ["eph"])
        add(.init(englishName: "Philippians",    indonesianName: "Filipi",               slug: "flp",  introRubric: "Bacaan dari Surat Rasul Paulus kepada Jemaat di Filipi.",           isGospel: false, isDeuterocanonical: false), aliases: ["phil"])
        add(.init(englishName: "Colossians",     indonesianName: "Kolose",               slug: "kol",  introRubric: "Bacaan dari Surat Rasul Paulus kepada Jemaat di Kolose.",           isGospel: false, isDeuterocanonical: false), aliases: ["col"])
        add(.init(englishName: "1 Thessalonians",indonesianName: "1 Tesalonika",         slug: "1tes", introRubric: "Bacaan dari Surat Pertama Rasul Paulus kepada Jemaat di Tesalonika.",isGospel: false, isDeuterocanonical: false), aliases: ["1 thess", "1thess"])
        add(.init(englishName: "2 Thessalonians",indonesianName: "2 Tesalonika",         slug: "2tes", introRubric: "Bacaan dari Surat Kedua Rasul Paulus kepada Jemaat di Tesalonika.", isGospel: false, isDeuterocanonical: false), aliases: ["2 thess", "2thess"])
        add(.init(englishName: "1 Timothy",      indonesianName: "1 Timotius",           slug: "1tim", introRubric: "Bacaan dari Surat Pertama Rasul Paulus kepada Timotius.",           isGospel: false, isDeuterocanonical: false), aliases: ["1 tim"])
        add(.init(englishName: "2 Timothy",      indonesianName: "2 Timotius",           slug: "2tim", introRubric: "Bacaan dari Surat Kedua Rasul Paulus kepada Timotius.",             isGospel: false, isDeuterocanonical: false), aliases: ["2 tim"])
        add(.init(englishName: "Titus",          indonesianName: "Titus",                slug: "tit",  introRubric: "Bacaan dari Surat Rasul Paulus kepada Titus.",                     isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Philemon",       indonesianName: "Filemon",              slug: "flm",  introRubric: "Bacaan dari Surat Rasul Paulus kepada Filemon.",                   isGospel: false, isDeuterocanonical: false), aliases: ["phlm"])
        add(.init(englishName: "Hebrews",        indonesianName: "Ibrani",               slug: "ibr",  introRubric: "Bacaan dari Surat kepada Orang Ibrani.",                           isGospel: false, isDeuterocanonical: false), aliases: ["heb"])
        add(.init(englishName: "James",          indonesianName: "Yakobus",              slug: "yak",  introRubric: "Bacaan dari Surat Rasul Yakobus.",                                 isGospel: false, isDeuterocanonical: false), aliases: ["jas"])
        add(.init(englishName: "1 Peter",        indonesianName: "1 Petrus",             slug: "1ptr", introRubric: "Bacaan dari Surat Pertama Rasul Petrus.",                          isGospel: false, isDeuterocanonical: false), aliases: ["1 pet", "1pet"])
        add(.init(englishName: "2 Peter",        indonesianName: "2 Petrus",             slug: "2ptr", introRubric: "Bacaan dari Surat Kedua Rasul Petrus.",                            isGospel: false, isDeuterocanonical: false), aliases: ["2 pet", "2pet"])
        add(.init(englishName: "1 John",         indonesianName: "1 Yohanes",            slug: "1yoh", introRubric: "Bacaan dari Surat Pertama Rasul Yohanes.",                         isGospel: false, isDeuterocanonical: false), aliases: ["1 jn", "1jn"])
        add(.init(englishName: "2 John",         indonesianName: "2 Yohanes",            slug: "2yoh", introRubric: "Bacaan dari Surat Kedua Rasul Yohanes.",                           isGospel: false, isDeuterocanonical: false), aliases: ["2 jn", "2jn"])
        add(.init(englishName: "3 John",         indonesianName: "3 Yohanes",            slug: "3yoh", introRubric: "Bacaan dari Surat Ketiga Rasul Yohanes.",                          isGospel: false, isDeuterocanonical: false), aliases: ["3 jn", "3jn"])
        add(.init(englishName: "Jude",           indonesianName: "Yudas",                slug: "yud",  introRubric: "Bacaan dari Surat Rasul Yudas.",                                   isGospel: false, isDeuterocanonical: false))
        add(.init(englishName: "Revelation",     indonesianName: "Wahyu",                slug: "why",  introRubric: "Bacaan dari Kitab Wahyu.",                                         isGospel: false, isDeuterocanonical: false), aliases: ["rev", "apocalypse"])

        return map
    }()
    // swiftlint:enable line_length
}
