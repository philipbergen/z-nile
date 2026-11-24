// fsevents-meter helper: counts file events under each root until it is told to stop.
// usage: fsevents-meter-helper <ready-file> <root>...   (stops on SIGTERM or SIGINT)
// prints one line per root on stop: "<count>\t<root as given>". Reads only; writes the ready file.
import CoreServices
import Foundation

final class Counter {
    var count = 0
    var real = ""
    var tally: [String: Int] = [:]  // events by the first `depth` folders under the root (FSEVENTS_METER_DEPTH)
}
let depth = Int(ProcessInfo.processInfo.environment["FSEVENTS_METER_DEPTH"] ?? "") ?? 0

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: fsevents-meter-helper <ready-file> <root>...\n".data(using: .utf8)!)
    exit(64)
}
let readyFile = args[0]
let roots = Array(args.dropFirst())
var counters: [Counter] = []
var streams: [FSEventStreamRef] = []
let queue = DispatchQueue(label: "fsevents-meter")

for root in roots {
    let counter = Counter()
    counters.append(counter)
    var buf = [Int8](repeating: 0, count: Int(PATH_MAX))
    let real = realpath(root, &buf) != nil ? String(cString: buf) : root
    var context = FSEventStreamContext(
        version: 0, info: Unmanaged.passUnretained(counter).toOpaque(), retain: nil, release: nil, copyDescription: nil)
    counter.real = real
    let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        let c = Unmanaged<Counter>.fromOpaque(info!).takeUnretainedValue()
        c.count += numEvents
        if depth > 0 {
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            for p in paths {
                var rel = p.hasPrefix(c.real) ? String(p.dropFirst(c.real.count)) : p
                rel = rel.split(separator: "/", omittingEmptySubsequences: true).prefix(depth).joined(separator: "/")
                c.tally[rel, default: 0] += 1
            }
        }
    }
    guard
        let stream = FSEventStreamCreate(
            nil, callback, &context, [real] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes))
    else {
        FileHandle.standardError.write("cannot watch \(root)\n".data(using: .utf8)!)
        exit(65)
    }
    FSEventStreamSetDispatchQueue(stream, queue)
    if !FSEventStreamStart(stream) {
        FileHandle.standardError.write("cannot start the stream for \(root)\n".data(using: .utf8)!)
        exit(65)
    }
    streams.append(stream)
}

// Runs on the main queue, never the streams' queue: FSEventStreamFlushSync from inside a busy stream's own queue
// blocked for good under a heavy load, so the stream is given its latency to deliver and the counts are read through the queue.
func finish() {
    usleep(300_000)
    let counts = queue.sync { counters.map { $0.count } }
    let tallies = queue.sync { counters.map { $0.tally } }
    for (i, root) in roots.enumerated() {
        print("\(counts[i])\t\(root)")
        for (folder, n) in tallies[i].sorted(by: { $0.value > $1.value }) { print("folder\t\(n)\t\(root)/\(folder)") }
    }
    fflush(stdout)
    exit(0)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: DispatchQueue.main)
    source.setEventHandler { finish() }
    source.resume()
    sources.append(source)
}
FileManager.default.createFile(atPath: readyFile, contents: Data())
dispatchMain()
