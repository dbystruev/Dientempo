import Foundation

enum SpanishNumberFormatter {
    private static let units = [
        "cero",
        "uno",
        "dos",
        "tres",
        "cuatro",
        "cinco",
        "seis",
        "siete",
        "ocho",
        "nueve"
    ]

    private static let teens = [
        10: "diez",
        11: "once",
        12: "doce",
        13: "trece",
        14: "catorce",
        15: "quince",
        16: "dieciséis",
        17: "diecisiete",
        18: "dieciocho",
        19: "diecinueve"
    ]

    private static let twenties = [
        20: "veinte",
        21: "veintiuno",
        22: "veintidós",
        23: "veintitrés",
        24: "veinticuatro",
        25: "veinticinco",
        26: "veintiséis",
        27: "veintisiete",
        28: "veintiocho",
        29: "veintinueve"
    ]

    private static let tens = [
        30: "treinta",
        40: "cuarenta",
        50: "cincuenta",
        60: "sesenta",
        70: "setenta",
        80: "ochenta",
        90: "noventa"
    ]

    static func words(for number: Int) -> String {
        precondition((0...200).contains(number), "Dientempo supports numbers from 0 through 200.")

        if number < 10 {
            return units[number]
        }

        if let teen = teens[number] {
            return teen
        }

        if let twenty = twenties[number] {
            return twenty
        }

        if number < 100 {
            let ten = (number / 10) * 10
            let unit = number % 10

            guard unit > 0 else {
                return tens[ten]!
            }

            return "\(tens[ten]!) y \(units[unit])"
        }

        if number == 100 {
            return "cien"
        }

        if number < 200 {
            return "ciento \(words(for: number - 100))"
        }

        return "doscientos"
    }
}
