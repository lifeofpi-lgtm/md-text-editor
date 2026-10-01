import Foundation
// usage: debugcmd "select|Proposal"  (debug builds of MDmaster only)
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("MDmaster.debug"), object: nil,
    userInfo: ["cmd": CommandLine.arguments.dropFirst().joined(separator: " ")], deliverImmediately: true)
