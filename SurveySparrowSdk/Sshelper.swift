//
//  SsSurveyDelegate.swift
//  SurveySparrowSdk
//
//  Created by Ajay Sivan on 05/06/20.
//  Copyright © 2020 SurveySparrow. All rights reserved.
//

import Foundation
func validateSurvey(domain: String? = nil, 
    token: String? = nil,
    params: [String: String]? = [:],
    group: DispatchGroup,
    completion: @escaping ([String: Any]) -> Void
    ) 
{
    struct User: Codable {
        let email: String
    }
    struct ValidationResponse: Codable {
        let active: Bool
        let reason: String
    }
    var email: String = "";
    var active: Bool = false;
    if let unwrappedParams = params {
    for (key, value) in unwrappedParams {
        if key == "emailaddress" {
            email = value
            break
        }
     }
    }
    DispatchQueue.global().async {
        let parameters = User(email: email)
        var urlComponent = URLComponents()
        urlComponent.scheme = "https"
        urlComponent.host = domain!.trimmingCharacters(in: CharacterSet.whitespaces)
        urlComponent.path = "/sdk/validate-survey/\(token!.trimmingCharacters(in: CharacterSet.whitespaces))"
        var validationUrl:URLRequest

        if let url = urlComponent.url {
            validationUrl = URLRequest(url: url);
            makeHTTPRequest(urlString: validationUrl.description, parameters: parameters) { result in
                defer {
                    group.leave()
                }
                
                switch result {
                case .success(let data):
                    if let data = data, let stringResponse = String(data: data, encoding: .utf8) {
                        guard let jsonData = stringResponse.data(using: .utf8) else {
                            print("Failed to convert string to data")
                        return
                        }
                        do {
                        let responseData = try JSONDecoder().decode(ValidationResponse.self, from: jsonData);
                        active = responseData.active;
                            var result = [
                            "active":responseData.active,
                            "reason":responseData.reason,
                            ] 
                            completion(result)
                            return
                        } catch {
                            print("Error decoding JSON: \(error)")
                        }
                        return
                    }
                case .failure(let error):
                    print("Error: \(error)")
                }
            }
        }   
    }
}

func makeHTTPRequest(urlString: String, parameters: Encodable, completion: @escaping (Result<Data?, Error>) -> Void) {
    // Create the URL
    guard let url = URL(string: urlString) else {
        completion(.failure(NSError(domain: urlString, code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    do {
        let jsonData = try JSONEncoder().encode(parameters)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
    } catch {
        completion(.failure(error))
        return
    }
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }     
        completion(.success(data))
    }
    task.resume()
}
