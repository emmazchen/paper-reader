import Foundation
import CoreServices
let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Paper Reader.app")
let status = LSRegisterURL(url as CFURL,true)
print("Registration status: \(status)")
if let handlers = LSCopyAllRoleHandlersForContentType("com.adobe.pdf" as CFString, .all)?.takeRetainedValue() as? [String] {
    print("Paper Reader registered for PDF: \(handlers.contains("local.paperreader.app"))")
}
exit(status == 0 ? 0 : 1)
