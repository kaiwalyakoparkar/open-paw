import Foundation
import OpenPawCore

enum TTSChunkBufferChecks {
    static func run() {
        var buf = TTSChunkBuffer(minChars: 40, maxChars: 100)
        assert(buf.pushFirst("Sure thing! ") == ["Sure thing!"])

        buf = TTSChunkBuffer(minChars: 30, maxChars: 100)
        assert(buf.pushFirst("Hi").isEmpty)
        assert(buf.push(". And this is the rest of the answer. ") == ["Hi. And this is the rest of the answer."])

        buf = TTSChunkBuffer(minChars: 80, maxChars: 200)
        _ = buf.push("One. Two. Three. Four. Five. Six. ")
        assert(buf.flush() == nil)

        print("TTSChunkBuffer OK")
    }
}
