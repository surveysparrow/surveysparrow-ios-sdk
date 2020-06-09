# Survey Sparrow iOS SDK

SurveySparrow iOS SDK enables you to collect the feedback from your mobile app. Embed the Classic & Chat surveys in your iOS application seamlessly with few lines of code.

> Mobile SDK share channel is only available from SurveySparrow **Premium** plan onwards.

## Features
1. [Full-screen feedback whenever & wherever you want.](#Full-screen-feedback)
2. [Integrate the feedback experience anywhere in your app.](#Embed-survey)
3. [Schedule Surveys to take one-time or recurring feedbacks.](#Schedule-Surveys)

## SDK integration (Deployment Target 9+)

### Add SurveySparrowSdk Framework
Add SurveySparrowSdk Framework to your project either by using CocoaPods or directly embed binary
#### Using CocoaPods
Add the following line to your `Podfile` file under `target`
```swift
pod 'SurveySparrowSdk', :git => 'URL', :tag => '0.1.0'
```

#### Embed SurveySparrowSdk Binary
Add `SurveySparrowSdk.framework` to your project

### Full-screen feedback
Take feedback using our pre-build `SsSurveyViewController` and get the response after submission by implementing the `SsSurveyDelegate`'s `handleSurveyResponse` protocol.

#### Import framework
```swift
import SurveySparrowSdk
```
#### Create a [`SsSurveyViewController`](#SsSurveyViewController)
Create a `SsSurveyViewController` and set `domain` and `token`
```swift
let ssSurveyViewController = SsSurveyViewController()
ssSurveyViewController.domain = "<account-domain>"
ssSurveyViewController.token = "<sdk-token>"
```
#### Present the SsSurveyViewController
```swift
present(ssSurveyViewController, animated: true, completion: nil)
```

#### Handle response
Implement the `SsSurveyDelegate` protocol to handle survey responses.
```swift
class ViewController: UIViewController, SsSurveyDelegate {
  //...
  func handleSurveyResponse(response: [String : Any]) {
    // Handle response here
    print(response)
  }
  //...
}
```
Also set surveyDelegate property of the `SsSurveyViewController` object to `self`
```swift
ssSurveyViewController.surveyDelegate = self
```

### Embed survey 
Embed the feedback experience using the [`SsSurveyView`](#SsSurveyView).

#### Add SsSurveyView
Add a `UIView` to storyboard and change the Class to `SsSurveyView` under *Identity Inspector*, make survey that the Module is `SurveySparrowSdk`. Under Attribute inspector tab specify `domain` and `token`. 

Now connect the `SsSurveyView` as an `IBOutlet`
```swift
@IBOutlet weak var ssSurveyView: SsSurveyView!
```
Then call `loadSurvey()` on on the `ssSurveyView` to load the survey
```swift
ssSurveyView.loadSurvey()
```
#### Handle response
Implement `SsSurveyDelegate` protocol to handle responses.

### Schedule Surveys
Ask the user to take a feedback survey when they open your app after few days.

Override viewDidAppear method and create a `SurveySparrow` object by passing domain and `token`. Then call `scheduleSurvey` method on the `SurveySparrow` object by passing the `ViewController` reference to schedule the survey.
```swift
override func viewDidAppear(_ animated: Bool) {
  super.viewDidAppear(animated)
  
  let surveySparrow = SurveySparrow(domain: "some-company.surveysparrow.com", token: "tt-7f76bd")
  surveySparrow.scheduleSurvey(parent: self)
}
```
Refer [SurveySparrow](#SurveySparrow) class for configuration options.

#### Handle response
Implement `SsSurveyDelegate` protocol to handle responses.

#### Cancel a schedule
You can cancel a schedule by calling the `surveySparrow.clearSchedule()` method.

#### How scheduling works
We will show a customized alert to take a feedback survey whenever the `scheduleSurvey` method called after the `startAfter` days and if the user declines to take the survey we will show the prompt after the `repeatInterval`.

**Example use case:** Add the above code to `viewDidAppear` method of your ViewController to ask the user to take a feedback survey 3 days after the user starts using your app, and if the user declines to take the survey we will continue to prompt at an interval of 5 days. If the user takes and complete the survey once we will not ask again.

**You can only create one schedule per token. Create multiple tokens if you want to create multiple schedules for same survey.*

## Reference
### SsSurveyView
View to display embedded surveys
#### Public Properties
|Property|Description|Default Value|
|-----------|------|------|
|`domain: String`|Your SurveySparrow account domain|*|
|`token: String`|SDK token of the survey|*|
|`params: [String: String]`|Custom params for the survey| - |
|`surveyDelegate: SsSurveyDelegate`|Protocol to handle survey response| - |

#### Public methods
|Method|Description|
|-----------|------|
|`loadSurvey(domain: String?, token: String?)`|Load survey in SsSurveyView|

### SsSurveyViewController
ViewController to take full-screen feedback
#### Public Properties
|Property|Description|Default Value|
|-----------|------|---|
|`domain: String`|Your SurveySparrow account domain| * |
|`token: String`|SDK token of the survey| * |
|`params: [String: String]`|Custom params for the survey| - |
|`thankyouTimeout: Double`|Duration to display thankyou screen in seconds| 3.0 |
|`surveyDelegate: SsSurveyDelegate`|Protocol to handle survey response| - |

#### Public methods
|Method|Description|
|-----------|------|
|`loadSurvey(domain: String?, token: String?)`|: Load survey in SsSurveyView|

### SsSurveyDelegate
Protocol to get survey responses
|Method|Description|
|-----------|------|
|`handleSurveyResponse(response: [String: Any])`|Handle survey response|

### SurveySparrow
Class to handle survey scheduling

#### Initializer
`public init(domain: String, token: String)` : pass SurveySparrow account domain & survey SDK token

#### Public Properties
|Property|Description|Default Value|
|-----------|------|------|
|`params: [String: String]`|Custom params for the survey| - |
|`thankyouTimeout: Double`|Duration to display thankyou screen in seconds| 3.0 |
|`surveyDelegate: SsSurveyDelegate`|Protocol to handle survey response| - |
|`alertTitle: String`| Alert title | Rate us |
|`alertMessage: String`| Alert message | Share your feedback and let us know how we are doing |
|`alertPositiveButton: String`| Alert positive button text | Rate Now |
|`alertNegativeButton: String`| Alert negative button text | Later |
|`isConnectedToNetwork: Bool`| Network status | true |
|`startAfter: Int`| Set the number of days to wait before showing the scheduled alert after launching the app for first time | 3 |
|`repeatInterval: Int`| Set the number of days to wait to show the dialog once the user declined the dialog or accepted in the case of multiple feedback enabled | 5 |
|`repeatSurvey: Bool`| Collect scheduled feedback multiple times. (Make sure that you have enabled 'Allow multiple submissions per user' for this survey) | false |
|`incrementalRepeat: Bool`| Repeat survey with a incremental interval | false |

#### Public methods
|Method|Description|
|-----------|------|
|`scheduleSurvey(parent: UIViewController)`|Schedule Survey|
|`clearSchedule()`|Clear scheduler data|

\* Required property

\- Optional


> Please submit bugs/issues through GitHub issues we will try to fix it ASAP.