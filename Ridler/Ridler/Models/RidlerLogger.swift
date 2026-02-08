import os

enum RidlerLogger {
    static let subsystem = "com.amattn.ridler"

    static let loop = Logger(subsystem: subsystem, category: "loop")
    static let prd = Logger(subsystem: subsystem, category: "prd")
    static let process = Logger(subsystem: subsystem, category: "process")
    static let git = Logger(subsystem: subsystem, category: "git")
}
