import UIKit
import SurveySparrowSdk
import SwiftUI

@available(iOS 15.0, *)
var spotCheck = Spotcheck(
    domainName: "your-domain",
    targetToken: "your-token",
    userDetails: [:]
)

@available(iOS 15.0, *)
class ViewController: UIViewController, SsSurveyDelegate {
    
    var hostingController: UIHostingController<Spotcheck>?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        spotCheck.TrackScreen(screen: "PaymentScreen")
        let hostingController = UIHostingController(rootView: spotCheck)
        self.hostingController = UIHostingController(rootView: spotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }

    // Action to trigger SpotCheck navigation
    @IBAction func showSpotCheck(_ sender: UIButton) {
        performSegue(withIdentifier: "showSpotCheck", sender: self)
    }
    

    // Action for the second SpotCheck button (if needed)
    @IBAction func showSpotCheck2(_ sender: UIButton) {
        performSegue(withIdentifier: "showSpotCheck2", sender: self)
    }

    var domain: String = "your-domain"
    var token: String = "your-token"

    @IBOutlet weak var ssSurveyView: SsSurveyView!

    // Action to show the full-screen survey
    @IBAction func showFullScreenSurvey(_ sender: UIButton) {
        let ssSurveyViewController = SsSurveyViewController()
        ssSurveyViewController.domain = domain
        ssSurveyViewController.token = token
        ssSurveyViewController.params = ["emailaddress": "email@email.com", "email": "email@email.com"]
        ssSurveyViewController.getSurveyLoadedResponse = true
        ssSurveyViewController.surveyDelegate = self
        present(ssSurveyViewController, animated: true, completion: nil)
    }

    // Action to start a survey
    @IBAction func startSurvey(_ sender: UIButton) {
        ssSurveyView.loadFullscreenSurvey(
            parent: self,
            delegate: self,
            domain: domain,
            token: token,
            params: ["emailaddress": "email@email.com", "email": "email@email.com"]
        )
    }

    // Action to show the embedded survey
    @IBAction func showEmbedSurvey(_ sender: UIButton) {
        ssSurveyView.loadEmbedSurvey(
            domain: domain,
            token: token,
            params: ["emailaddress": "email@email.com", "email": "email@email.com"]
        )
    }

    // Delegate methods to handle survey responses
    func handleSurveyResponse(response: [String: AnyObject]) {
        print("ViewController: Survey Response:", response)
    }

    func handleSurveyLoaded(response: [String: AnyObject]) {
        print("ViewController: Survey Loaded:", response)
    }

    func handleSurveyValidation(response: [String: AnyObject]) {
        print("ViewController: Survey Validation:", response)
    }

    func handleCloseButtonTap() {
        print("ViewController: HandleCloseButton Tap")
    }
}







@available(iOS 15.0, *)
struct SpotCheckView: View {
    var body: some View {
        VStack {
            spotCheck
        }
    }
}

@available(iOS 16.0, *)
class SpotCheckScreen: UIViewController {
    var hostingController: UIHostingController<Spotcheck>?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        spotCheck.TrackScreen(screen: "PaymentScreen")
       
        let hostingController = UIHostingController(rootView: spotCheck)
        self.hostingController = UIHostingController(rootView: spotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Force the hosting controller to update its layout
        hostingController?.view.setNeedsLayout()
        hostingController?.view.layoutIfNeeded()
    }
    
    

        @IBAction func click(_ sender: Any) {
            spotCheck.TrackEvent(onScreen: "PaymentScreen", event: ["MobileClick": []])
            
            let hostingController = UIHostingController(rootView: spotCheck)
            self.hostingController = UIHostingController(rootView: spotCheck)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.view.backgroundColor = UIColor.clear
            present(hostingController, animated: true, completion: nil)
        }
        
}





@available(iOS 15.0, *)
class PaymentScreen: UIViewController {

    // Action to trigger payment tracking
    @IBAction func paymentDone(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "PaymentScreen", event: ["MobileClick": []])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Track the PaymentScreen when it appears
        spotCheck.TrackScreen(screen: "PaymentScreen")
    }
    
}






