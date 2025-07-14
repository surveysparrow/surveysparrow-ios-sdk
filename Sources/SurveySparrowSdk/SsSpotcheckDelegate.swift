import Foundation

@available(iOS 13.0, *)
public protocol SsSpotcheckDelegate {
    func handleSurveyResponse(response: [String: AnyObject]) async
    func handleSurveyLoaded(response: [String: AnyObject]) async
    func handleCloseButtonTap() async
    func handlePartialSubmission(response: [String: AnyObject]) async
}

@available(iOS 13.0, *)
public extension SsSpotcheckDelegate {
    func handleSurveyResponse(response: [String: AnyObject]) async {}
    func handleSurveyLoaded(response: [String: AnyObject]) async {}
    func handleCloseButtonTap() async {}
    func handlePartialSubmission(response: [String: AnyObject]) async {}
}
