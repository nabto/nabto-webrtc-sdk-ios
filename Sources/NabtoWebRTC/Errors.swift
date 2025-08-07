import Foundation

/**
  * This an encapsulation of Http Errors which can come from invoking the Nabto WebRTC Signaling Service.
  *
  * @param statusCode the http status code of the error.
  * @param message the messsga describing the error.
  */
public enum HttpError: LocalizedError {
    /**
      * Thrown if the devuce id is not found in the Nabto WebRTC Signaling Service.
      *
      * @param statusCode the http status code.
      * @param message the friendly message describing the error.
      */
    case deviceIdNotFound(statusCode: Int, message: String)
    
    /**
      * Thrown if the product id is not found in the Nabto WebRTC Signaling Service.
      *
      * @param statusCode the http status code.
      * @param message the friendly message describing the error.
      */
    case poductIdNotFound(statusCode: Int, message: String)
    
    /**
      * Thrown if some other HTTP error was returned from the Nabto WebRTC Signaling Service.
      *
      * @param statusCode the http status code.
      * @param message the friendly message describing the error.
      */
    case unknown(statusCode: Int, message: String? = nil)
    
    public var errorDescription: String? {
        switch self {
        case let .deviceIdNotFound(_, message):
            return message
        case let .poductIdNotFound(_, message):
            return message
        case let .unknown(statusCode, message):
            if let message = message {
                return message
            }
            return "HTTP request to Nabto WebRTC failed, status code: \(statusCode)"
        }
    }
}

/**
  * Thrown if the device is offline but was required to be online while connecting to the
  * Nabto WebRTC signaling Service.
  */
public struct DeviceOfflineError: LocalizedError {
    public var errorDescription: String? = "The requested device is offline, but the requireOnline bit was set."
}
