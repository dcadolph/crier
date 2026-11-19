#if CRIER_MEASURE
    import Foundation

    import CrierKit

    // MeasureLog appends the biggest headlines of every refresh to a file per day and rewrites summary.txt beside
    // them. Only builds made with the CRIER_MEASURE flag have it, so the shipped app never writes these files.
    actor MeasureLog {
        // folder holds the day files and the summary.
        let folder: URL

        // init writes into the folder, by default Application Support/Crier/measure.
        init(folder: URL = MeasureLog.defaultFolder) {
            self.folder = folder
        }

        // defaultFolder is Application Support/Crier/measure in the reader's Library.
        static var defaultFolder: URL {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return support.appending(path: "Crier/measure", directoryHint: .isDirectory)
        }

        // record appends the records to the day's file and rewrites the summary from every day's file.
        func record(_ records: [Measure.Record]) {
            guard let at = records.first?.at else {
                return
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try append(Measure.lines(records), to: folder.appending(path: Measure.fileName(for: at)))
                try summarize()
            } catch {
                NSLog("crier: measuring log failed: %@", error.localizedDescription)
            }
        }

        // append adds the data to the end of the file, creating the file when it is missing.
        private func append(_ data: Data, to file: URL) throws {
            guard let handle = try? FileHandle(forWritingTo: file) else {
                try data.write(to: file)
                return
            }
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }

        // summarize reads every day file and writes summary.txt.
        private func summarize() throws {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }
            let records = try files.flatMap { Measure.decode(try Data(contentsOf: $0)) }
            try Data(Measure.summary(records).utf8).write(to: folder.appending(path: "summary.txt"), options: .atomic)
        }
    }
#endif
