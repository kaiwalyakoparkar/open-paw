import Foundation

enum GradiumSTTChunkingChecks {
    static func run() {
        let chunk = 1920 * 2
        var pending = Data()
        var sent: [Int] = []
        func sendAudio(_ pcm: Data) {
            pending.append(pcm)
            while pending.count >= chunk {
                sent.append(chunk)
                pending.removeFirst(chunk)
            }
        }
        sendAudio(Data(count: chunk / 2))
        assert(sent.isEmpty)
        sendAudio(Data(count: chunk))
        assert(sent == [chunk])
        assert(pending.count == chunk / 2)
        print("GradiumSTTChunking OK")
    }
}
