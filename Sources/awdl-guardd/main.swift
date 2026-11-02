import AWDLCore
import Foundation

guard getuid() == 0 else {
    FileHandle.standardError.write("awdl-guardd must run as root (it is started by launchd)\n".data(using: .utf8)!)
    exit(1)
}

guard let daemon = Daemon(monitor: AWDLMonitor()) else {
    FileHandle.standardError.write("Failed to initialise AWDL monitor\n".data(using: .utf8)!)
    exit(1)
}
daemon.start()
dispatchMain()
