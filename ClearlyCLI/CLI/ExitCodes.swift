import ArgumentParser

enum Exit {
    static let success: Int32 = 0
    static let general: Int32 = 1
    static let usage: Int32 = 2
    static let notFound: Int32 = 3
    static let permission: Int32 = 4
    static let conflict: Int32 = 5
}
