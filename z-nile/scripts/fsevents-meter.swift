// fsevents-meter helper: counts file events under each root until it is told to stop.
// usage: fsevents-meter-helper <ready-file> <root>...   (stops on SIGTERM or SIGINT)
// prints one line per root on stop: "<count>\t<root as given>". Reads only; writes the ready file.
import CoreServices
import Foundation

final class Counter {
    var count = 0
}

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
    let real = (root as NSString).resolvingSymlinksInPath
    var context = FSEventStreamContext(
        version: 0, info: Unmanaged.passUnretained(counter).toOpaque(), retain: nil, release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, numEvents, _, _, _ in
        Unmanaged<Counter>.fromOpaque(info!).takeUnretainedValue().count += numEvents
    }
    guard
        let stream = FSEventStreamCreate(
            nil, callback, &context, [real] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
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

func finish() {
    for stream in streams { FSEventStreamFlushSync(stream) }
    for (i, root) in roots.enumerated() { print("\(counters[i].count)\t\(root)") }
    fflush(stdout)
    exit(0)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    source.setEventHandler { finish() }
    source.resume()
    sources.append(source)
}
FileManager.default.createFile(atPath: readyFile, contents: Data())
dispatchMain()
