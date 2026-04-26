//  MassReading.swift
//  BibleApp
//
//  Created by Yohanes Sitanggang on 08/04/26.
//

import Foundation

// MARK: - Liturgical Season

enum LiturgicalSeason: String, Codable {
    case ordinaryTime = "ordinary_time"
    case advent       = "advent"
    case lent         = "lent"
    case easter       = "easter"
    case christmas    = "christmas"
    case feastDay     = "feast_day"
}

// MARK: - Reading Type

enum ReadingType: String, Codable {
    case firstReading  = "BACAAN 1"
    case psalm         = "MAZMUR TANGGAPAN"
    case secondReading = "BACAAN 2"
    case gospel        = "BACAAN INJIL"
    case alleluia      = "BAIT PENGANTAR INJIL"
}

// MARK: - Mass Reading

struct MassReading: Identifiable, Codable {
    let id: UUID
    let type: ReadingType
    let reference: String
    let introRubric: String
    let bodyText: String
    let responseRubric: String?
    let congregationResponse: String?

    init(
        id: UUID = UUID(),
        type: ReadingType,
        reference: String,
        introRubric: String,
        bodyText: String,
        responseRubric: String? = nil,
        congregationResponse: String? = nil
    ) {
        self.id = id
        self.type = type
        self.reference = reference
        self.introRubric = introRubric
        self.bodyText = bodyText
        self.responseRubric = responseRubric
        self.congregationResponse = congregationResponse
    }
}

// MARK: - Mass Day

struct MassDay: Codable {
    let date: Date
    let celebrationName: String
    let season: LiturgicalSeason
    let readings: [MassReading]
}

// MARK: - Sample Data

extension MassDay {
    static let sample = MassDay(
        date: Date(),
        celebrationName: "Senin Dalam Oktaf Paskah",
        season: .easter,
        readings: [
            MassReading(
                type: .firstReading,
                reference: "Kis 2:14, 22-33",
                introRubric: "Bacaan dari Kisah Para Rasul.",
                bodyText: """
Pada hari Pentakosta, tampillah Petrus bersama kesebelas rasul itu, dan dengan suara nyaring ia berkata kepada mereka: "Hai kamu orang Yahudi dan kamu semua yang tinggal di Yerusalem, ketahuilah dan camkanlah perkataanku ini. Hai orang-orang Israel, dengarlah perkataan ini: Yang aku maksudkan, ialah Yesus dari Nazaret, seorang yang telah ditentukan Allah dan yang dinyatakan kepadamu dengan kekuatan-kekuatan dan mujizat-mujizat dan tanda-tanda yang dilakukan oleh Allah dengan perantaraan Dia di tengah-tengah kamu, seperti yang kamu tahu.

Dia yang diserahkan Allah menurut maksud dan rencana-Nya, telah kamu salibkan dan kamu bunuh oleh tangan bangsa-bangsa durhaka. Tetapi Allah membangkitkan Dia dengan melepaskan Dia dari sengsara maut, karena tidak mungkin Ia tetap berada dalam kuasa maut itu.

Sebab Daud berkata tentang Dia: Aku senantiasa memandang kepada Tuhan, karena Ia berdiri di sebelah kananku, aku tidak goyah. Sebab itu hatiku bersukacita dan jiwaku bersorak-sorak, bahkan tubuhku akan diam dengan tenteram, sebab Engkau tidak menyerahkan aku kepada dunia orang mati, dan tidak membiarkan Orang Kudus-Mu melihat kebinasaan. Engkau memberitahukan kepadaku jalan kehidupan; Engkau akan melimpahi aku dengan sukacita di hadapan-Mu.
""",
                responseRubric: "Demikianlah sabda Tuhan.",
                congregationResponse: "Syukur kepada Allah."
            ),
            MassReading(
                type: .psalm,
                reference: "Mzm 16:1-2a, 5, 7-11",
                introRubric: "Mazmur Tanggapan",
                bodyText: """
R. Jagalah aku, ya Allah, sebab pada-Mu aku berlindung.

Jagalah aku, ya Allah, sebab pada-Mu aku berlindung.
Aku berkata kepada TUHAN: "Engkaulah Tuhanku,
tidak ada yang baik bagiku selain Engkau!"
TUHAN adalah bagian warisanku dan pialaku,
Engkau sendirilah yang meneguhkan bagian yang diundikan kepadaku.

R. Jagalah aku, ya Allah, sebab pada-Mu aku berlindung.

Aku memuji TUHAN, yang telah memberi nasihat kepadaku,
ya, pada waktu malam hati nuraniku mengajari aku.
Aku senantiasa memandang kepada TUHAN;
karena Ia berdiri di sebelah kananku, aku tidak goyah.

R. Jagalah aku, ya Allah, sebab pada-Mu aku berlindung.
"""
            ),
            MassReading(
                type: .gospel,
                reference: "Mrk 16:9-15",
                introRubric: "Inilah Injil Yesus Kristus menurut Markus.",
                bodyText: """
Setelah Yesus bangkit pada hari pertama minggu itu, Ia mula-mula menampakkan diri-Nya kepada Maria Magdalena. Ia pernah mengusir tujuh setan dari perempuan itu. Perempuan itu pergi memberitahukannya kepada mereka yang selalu bersama-sama dengan Yesus, yang sedang berkabung dan menangis. Tetapi ketika mereka mendengar, bahwa Yesus hidup dan telah dilihat olehnya, mereka tidak percaya.

Sesudah itu Ia menampakkan diri dalam rupa yang lain kepada dua orang dari mereka, ketika keduanya dalam perjalanan ke luar kota. Lalu keduanya kembali dan memberitahukannya kepada teman-teman yang lain, tetapi mereka pun tidak dipercayai.

Kemudian Ia menampakkan diri kepada kesebelas orang itu ketika mereka sedang makan, dan Ia mencela ketidakpercayaan dan kekerasan hati mereka, oleh karena mereka tidak percaya kepada orang-orang yang telah melihat Dia sesudah kebangkitan-Nya. Lalu Ia berkata kepada mereka: "Pergilah ke seluruh dunia, beritakanlah Injil kepada segala makhluk."
""",
                responseRubric: "Demikianlah Injil Tuhan.",
                congregationResponse: "Terpujilah Kristus."
            )
        ]
    )
}
