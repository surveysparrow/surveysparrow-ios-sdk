import Foundation

public protocol SsSpotcheckDelegate {
    func handleSurveyResponse(response: [String: AnyObject]) async
    func handleSurveyLoaded(response: [String: AnyObject]) async
    func handleCloseButtonTap() async
}

public extension SsSpotcheckDelegate {
    func handleSurveyResponse(response: [String: AnyObject]) async {}
    func handleSurveyLoaded(response: [String: AnyObject]) async {}
    func handleCloseButtonTap() async {}
}
