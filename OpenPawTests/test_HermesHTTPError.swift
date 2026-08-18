import OpenPawCore
import Foundation

enum HermesHTTPErrorChecks {
    static func run() {
        let auth = HermesHTTPError.parse(
            body: #"{"error":{"message":"Invalid API key","code":"invalid_api_key"}}"#,
            status: 401
        )
        assert(auth == .unauthorized, "401: \(String(describing: auth))")

        let big = HermesHTTPError.parse(
            body: #"{"error":{"message":"Request body too large.","code":"body_too_large"}}"#,
            status: 413
        )
        assert(big == .payloadTooLarge, "413: \(String(describing: big))")

        let ok = HermesHTTPError.parse(body: "{}", status: 200)
        assert(ok == nil)

        print("HermesHTTPError OK")
    }
}

extension HermesHTTPError: Equatable {
    public static func == (lhs: HermesHTTPError, rhs: HermesHTTPError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized), (.payloadTooLarge, .payloadTooLarge):
            return true
        case (.status(let a, let am), .status(let b, let bm)):
            return a == b && am == bm
        default:
            return false
        }
    }
}
