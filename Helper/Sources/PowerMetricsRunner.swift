import Foundation

/// Runs `powermetrics` as root and turns its streaming plist output into
/// `EnergySnapshot`s (spec §6.1).
///
/// `powermetrics --samplers tasks -i 5000 -f plist` emits one XML plist document per
/// sample on stdout, back-to-back. We buffer stdout, split it into complete
/// `<?xml…</plist>` documents, and parse each with `PropertyListSerialization`.
///
/// Plist keys for per-task energy differ across Apple Silicon / Intel and macOS versions,
/// so parsing is defensive: probe several known key spellings, treat anything missing as
/// 0, and never crash on unexpected structure (spec §6.1).
final class PowerMetricsRunner {

    private var process: Process?
    private var buffer = Data()
    /// Set by the owner after construction; each parsed sample is delivered here.
    var onSnapshot: ((EnergySnapshot) -> Void)?
    private var loggedUnknownStructure = false

    var isRunning: Bool { process?.isRunning ?? false }

    func start(intervalMillis: Int = 5000) {
        guard process == nil else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        proc.arguments = [
            "--samplers", "tasks",
            "-i", String(intervalMillis),
            "-f", "plist",
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.ingest(chunk)
        }

        do {
            try proc.run()
            process = proc
        } catch {
            NSLog("Onke helper: failed to launch powermetrics: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        buffer.removeAll()
    }

    // MARK: Streaming plist splitting

    private static let docTerminator = Data("</plist>".utf8)

    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        // Extract each complete document ending in </plist>.
        while let range = buffer.range(of: Self.docTerminator) {
            let docEnd = range.upperBound
            let doc = buffer.subdata(in: buffer.startIndex..<docEnd)
            buffer.removeSubrange(buffer.startIndex..<docEnd)
            parseDocument(doc)
        }
    }

    private func parseDocument(_ data: Data) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else { return }

        guard let tasks = dict["tasks"] as? [[String: Any]] else {
            if !loggedUnknownStructure {
                NSLog("Onke helper: powermetrics plist had no 'tasks' array; keys=\(Array(dict.keys))")
                loggedUnknownStructure = true
            }
            return
        }

        let processes: [ProcessEnergySample] = tasks.compactMap { task in
            guard let pid = intValue(task["pid"]) else { return nil }
            let name = (task["name"] as? String) ?? "pid \(pid)"
            let energy = energyImpact(from: task)
            return ProcessEnergySample(pid: Int32(pid), name: name, energyImpact: energy)
        }

        onSnapshot?(EnergySnapshot(timestamp: Date(), processes: processes))
    }

    /// Probe the several known spellings of the per-task energy field across platforms;
    /// fall back to CPU ms/s if no energy field is present. Missing → 0.
    private func energyImpact(from task: [String: Any]) -> Double {
        let energyKeys = ["energy_impact", "energy_impact_per_s", "energy"]
        for key in energyKeys {
            if let v = doubleValue(task[key]) { return v }
        }
        // Fallback proxy: CPU time per second (ms/s).
        if let v = doubleValue(task["cputime_ms_per_s"]) { return v }
        return 0
    }

    private func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
