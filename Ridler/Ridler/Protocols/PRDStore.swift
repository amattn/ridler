import Foundation

protocol PRDStore {
    func loadProject(from directoryURL: URL) throws -> PRDProject
    func loadMarkdown(filename: String, from directoryURL: URL) throws -> String
    func loadMarkdownIfExists(filename: String, from directoryURL: URL) -> String?
    func writeProject(_ project: PRDProject, to directoryURL: URL) throws
}
