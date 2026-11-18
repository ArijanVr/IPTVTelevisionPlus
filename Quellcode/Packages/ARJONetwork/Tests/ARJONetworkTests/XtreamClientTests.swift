import ARJOCore
import XCTest
@testable import ARJONetwork

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var requests: [URLRequest] = []
    let handler: (URLRequest) throws -> (Data, Int)

    init(_ handler: @escaping (URLRequest) throws -> (Data, Int)) { self.handler = handler }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class XtreamClientTests: XCTestCase {
    private let server = URL(string: "http://example.com:8080")!

    private func client(_ http: MockHTTPClient, password: String = "geheim") -> XtreamClient {
        XtreamClient(credentials: XtreamCredentials(serverURL: server, username: "anna", password: password), http: http)
    }

    private func json(_ text: String, status: Int = 200) -> MockHTTPClient {
        MockHTTPClient { _ in (Data(text.utf8), status) }
    }

    func testAuthenticatesAndMapsAccountInfo() async throws {
        let http = json("""
        {"user_info":{"username":"anna","password":"geheim","auth":1,"status":"Active",
         "exp_date":"1792859400","is_trial":"0","active_cons":"1","max_connections":"2",
         "allowed_output_formats":["m3u8","ts"]},
         "server_info":{"url":"example.com","timezone":"Europe/Zurich"}}
        """)
        let info = try await client(http).authenticate()
        XCTAssertEqual(info.username, "anna")
        XCTAssertEqual(info.expirationDate, Date(timeIntervalSince1970: 1_792_859_400))
        XCTAssertEqual(info.activeConnections, 1)
        XCTAssertEqual(info.maxConnections, 2)
        XCTAssertEqual(info.allowedOutputFormats, ["m3u8", "ts"])
        XCTAssertEqual(info.serverTimeZone, "Europe/Zurich")
        XCTAssertFalse(info.isTrial)
    }

    func testAcceptsNumbersAndNullsInsteadOfStrings() async throws {
        let http = json(#"{"user_info":{"username":"anna","auth":"1","status":"Active","exp_date":null,"is_trial":0,"max_connections":3}}"#)
        let info = try await client(http).authenticate()
        XCTAssertNil(info.expirationDate)
        XCTAssertEqual(info.maxConnections, 3)
    }

    func testRequestEncodesSpecialCharactersInPassword() async throws {
        let http = json(#"{"user_info":{"username":"anna","auth":1,"status":"Active"}}"#)
        _ = try await client(http, password: "p&ss+wörd=1 #").authenticate()
        let url = try XCTUnwrap(http.requests.first?.url)
        XCTAssertEqual(url.path, "/player_api.php")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
            "username=anna&password=p%26ss%2Bw%C3%B6rd%3D1%20%23"
        )
    }

    func testAuthZeroMeansInvalidCredentials() async {
        await assertThrows(.invalidCredentials, json(#"{"user_info":{"auth":0}}"#))
    }

    func testHTTP401MeansInvalidCredentials() async {
        await assertThrows(.invalidCredentials, json("", status: 401))
    }

    func testInactiveAccount() async {
        await assertThrows(.accountInactive(status: "Expired"),
                           json(#"{"user_info":{"username":"anna","auth":1,"status":"Expired"}}"#))
    }

    func testOtherHTTPStatus() async {
        await assertThrows(.httpStatus(500), json("", status: 500))
    }

    func testHTMLResponseIsUnexpected() async {
        await assertThrows(.unexpectedResponse, json("<html>Willkommen</html>"))
    }

    func testNetworkErrorKeepsOnlyTheCode() async {
        let http = MockHTTPClient { _ in throw URLError(.timedOut) }
        await assertThrows(.network(.timedOut), http)
    }

    func testErrorsNeverContainPasswordOrURL() {
        let errors: [XtreamError] = [.invalidServerURL, .invalidCredentials, .accountInactive(status: "x"),
                                     .httpStatus(500), .network(.timedOut), .unexpectedResponse]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").contains("geheim"))
            XCTAssertFalse((error.errorDescription ?? "").contains("http"))
        }
    }

    func testCredentialsDescriptionHidesSecrets() {
        let text = "\(XtreamCredentials(serverURL: server, username: "anna", password: "geheim"))"
        XCTAssertFalse(text.contains("geheim"))
        XCTAssertFalse(text.contains("anna"))
    }

    func testNormalizesServerInput() throws {
        XCTAssertEqual(try XtreamServerURL.normalize("example.com:8080").absoluteString, "http://example.com:8080")
        XCTAssertEqual(try XtreamServerURL.normalize(" HTTPS://Example.com/c/?x=1 ").absoluteString, "https://example.com")
        XCTAssertEqual(try XtreamServerURL.normalize("http://example.com:80/player_api.php").absoluteString, "http://example.com:80")
    }

    func testRejectsInvalidServerInput() {
        for input in ["", "   ", "ftp://example.com", "http://"] {
            XCTAssertThrowsError(try XtreamServerURL.normalize(input), input) {
                XCTAssertEqual($0 as? XtreamError, .invalidServerURL)
            }
        }
    }

    private func assertThrows(_ expected: XtreamError, _ http: MockHTTPClient, line: UInt = #line) async {
        do {
            _ = try await client(http).authenticate()
            XCTFail("Fehler erwartet", line: line)
        } catch {
            XCTAssertEqual(error as? XtreamError, expected, line: line)
        }
    }
}
