import CoreGraphics
import Foundation
import AppKit

var maxTaps: UInt32 = 100
var tapList = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(maxTaps))
var actualCount: UInt32 = 0
let err = CGGetEventTapList(maxTaps, &tapList, &actualCount)
print("error=\(err.rawValue), total taps: \(actualCount)")

for i in 0..<Int(actualCount) {
    let tap = tapList[i]
    let pid = tap.tappingProcess
    var name = "?"
    if let app = NSRunningApplication(processIdentifier: pid) {
        name = app.localizedName ?? app.bundleIdentifier ?? "?"
    } else {
        var buffer = [CChar](repeating: 0, count: 2048)
        if proc_name(pid, &buffer, 2048) > 0 {
            name = String(cString: buffer)
        }
    }
    var interesting: [String] = []
    if tap.eventsOfInterest & (1 << 10) != 0 { interesting.append("keyDown") }
    if tap.eventsOfInterest & (1 << 11) != 0 { interesting.append("keyUp") }
    if tap.eventsOfInterest & (1 << 12) != 0 { interesting.append("flagsChanged") }
    if interesting.isEmpty { interesting.append("other") }
    print(String(format: "pid=%d name=%@ tapPoint=%d options=%d enabled=%d avgLatency=%.1fus maxLatency=%.1fus events=%@",
                 pid, name as NSString,
                 tap.tapPoint.rawValue, tap.options.rawValue,
                 tap.enabled ? 1 : 0,
                 tap.avgUsecLatency, tap.maxUsecLatency,
                 interesting.joined(separator: ",")))
}
