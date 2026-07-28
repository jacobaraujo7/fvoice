import Foundation

protocol TextInserter: AnyObject {
    /// Inserts text at the cursor of the frontmost app.
    func insert(_ text: String)
}
