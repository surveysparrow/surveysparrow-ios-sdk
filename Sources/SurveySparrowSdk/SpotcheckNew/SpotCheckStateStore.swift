import Foundation
import SwiftUI

@available(iOS 15.0, *)
final class SpotCheckStateStore: ObservableObject {
    @Published private(set) var state: [String: Any] = SpotCheckStateStore.initialState()

    static func initialState() -> [String: Any] {
        return [
            "SpotCheckState": [
                "allSpotChecksInToken": [] as [[String: Any]],
                "customEventsSpotChecks": [] as [[String: Any]],
                "filteredSpotChecks": [] as [[String: Any]],
                "showSpotCheck": false,
                "currentSpotcheck": [
                    "spotcheckURL": "",
                    "spotcheckID": 0,
                    "spotcheckContactID": 0,
                    "triggerToken": "",
                    "screenName": "",
                    "afterDelay": 0,
                    "isChat": false,
                    "appearance": [:] as [String: Any],
                ] as [String: Any],
                "params": [
                    "targetToken": "",
                    "domainName": "",
                    "userDetails": [:] as [String: Any],
                    "variables": [:] as [String: Any],
                    "customProperties": [:] as [String: Any],
                    "visitor": [:] as [String: Any],
                    "framework": "ios",
                    "userAgent": "",
                    "traceId": "",
                ] as [String: Any],
                "spotCheckDetails": [
                    "keyBoardHeight": 0,
                    "textPosition": 0,
                    "isMounted": false,
                    "isVisible": false,
                    "isExiting": false,
                    "currentQuestionHeight": 0,
                    "miniCardHeight": 0,
                    "sideTabButtonWidth": 0,
                    "isFullScreenMode": false,
                    "spotCheckType": "",
                    "position": "",
                    "mode": "",
                    "closeButton": [
                        "isEnabled": false,
                        "color": "#000000",
                        "isMiniCard": false,
                    ] as [String: Any],
                    "isSpotCheckButton": false,
                    "spotCheckButtonConfig": [:] as [String: Any],
                    "showSurveyContent": true,
                    "avatarEnabled": false,
                    "avatarUrl": "",
                    "isBannerImageOn": false,
                ] as [String: Any],
                "webViewDetails": [
                    "isChatEnabled": false,
                    "isClassicEnabled": false,
                    "isClassicLoading": true,
                    "isChatLoading": true,
                    "chatUrl": "",
                    "classicUrl": "",
                    "isCurrentSpotcheckChat": false,
                    "canShowClassic": true,
                    "canShowChat": false,
                    "webViewInjectionData": "" as Any,
                    "scrollEnabled": true,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    func getState() -> [String: Any] {
        return state
    }

    func dispatch(_ update: [String: Any]) {
        if Thread.isMainThread {
            mergeState(update)
        } else {
            DispatchQueue.main.async { [weak self] in self?.mergeState(update) }
        }
    }

    private func mergeState(_ update: [String: Any]) {
        guard var spotCheckState = state["SpotCheckState"] as? [String: Any] else { return }

        let nestedMergeKeys: Set<String> = ["params", "spotCheckDetails", "webViewDetails", "currentSpotcheck"]

        for (key, value) in update {
            if nestedMergeKeys.contains(key), let newDict = value as? [String: Any],
               var existing = spotCheckState[key] as? [String: Any] {
                for (k, v) in newDict {
                    existing[k] = v
                }
                spotCheckState[key] = existing
            } else {
                spotCheckState[key] = value
            }
        }

        state["SpotCheckState"] = spotCheckState
    }
}
