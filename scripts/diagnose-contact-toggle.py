#!/usr/bin/env python3
"""One nonshipping import-review toggle observation; never release validation."""
import importlib.util
import re
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("base", Path(__file__).with_name("diagnose-control-events.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
original_instrument = base.instrument
original_calibrate = base.calibrate
original_failure_category = base.failure_category


def instrument(*sources):
    test, clear, editor, content, app = original_instrument(*sources)
    before = '''        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: friendFrame.maxX - 35,dy: friendFrame.midY)).tap()
        XCTAssertEqual(friend.value as? String,"1")'''
    after = '''        Logger(subsystem: "com.kin.synthetic.marker", category: "control").notice("KIN_MARK target=friend stage=before ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: friendFrame.maxX - 35,dy: friendFrame.midY)).tap()
        let immediate = friend.value as? String
        Logger(subsystem: "com.kin.synthetic.control", category: "review").notice("KIN_OBSERVE stage=immediate value=\(immediate == "1" ? "on" : immediate == "0" ? "off" : "unknown", privacy: .public) ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        if immediate != "1" {
            let later = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in friend.value as? String == "1" }, object: nil)
            _ = XCTWaiter.wait(for: [later], timeout: 5)
            let observed = friend.value as? String
            Logger(subsystem: "com.kin.synthetic.control", category: "review").notice("KIN_OBSERVE stage=later value=\(observed == "1" ? "on" : observed == "0" ? "off" : "unknown", privacy: .public) ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        }
        Logger(subsystem: "com.kin.synthetic.marker", category: "control").notice("KIN_MARK target=friend stage=after ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        XCTAssertEqual(immediate,"1")'''
    test = base.replace_once(test, before, after)
    before = '                                if selected { reviewedConnections.insert(connection) } else { reviewedConnections.remove(connection) }\n'
    after = '''                                if connection == .friend { Logger(subsystem: "com.kin.synthetic.control", category: "review").notice("KIN_BIND stage=before selected=\(selected, privacy: .public) present=\(reviewedConnections.contains(connection), privacy: .public) ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)") }
                                if selected { reviewedConnections.insert(connection) } else { reviewedConnections.remove(connection) }
                                if connection == .friend { Logger(subsystem: "com.kin.synthetic.control", category: "review").notice("KIN_BIND stage=after selected=\(selected, privacy: .public) present=\(reviewedConnections.contains(connection), privacy: .public) ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)") }
'''
    editor = base.replace_once(editor, before, after)
    before = '                            })).accessibilityIdentifier("contact-connection-" + connection.rawValue)'
    after = '''                            })).accessibilityIdentifier("contact-connection-" + connection.rawValue)
                            .background {
                                if connection == .friend {
                                    GeometryReader { proxy in
                                        Color.clear.allowsHitTesting(false)
                                            .onAppear { ControlEventProbe.friend = proxy.frame(in: .global); ControlEventProbe.geometry("review") }
                                            .onChange(of: proxy.frame(in: .global)) { _, frame in ControlEventProbe.friend = frame }
                                    }
                                }
                            }'''
    editor = base.replace_once(editor, before, after)
    return test, clear, editor, content, app


def calibrate(events, target):
    marks = [e["uptime_ms"] for e in events if e["kind"] == "mark" and e["fields"] == [target, "before"]]
    review = any(e["kind"] == "geometry" and e["fields"] == ["review"] and marks and e["uptime_ms"] <= marks[0] for e in events)
    immediate = [e for e in events if e["kind"] == "observe" and e["fields"][0] == "immediate"]
    later = [e for e in events if e["kind"] == "observe" and e["fields"][0] == "later"]
    if len(immediate) != 1 or (immediate[0]["fields"][1] != "on" and len(later) != 1):
        return False
    # The ordinary editor's earlier geometry is not sufficient for this view.
    synthetic = [{"kind": "geometry", "fields": [target], "uptime_ms": 0}] if review else []
    return bool(review) and original_calibrate(events + synthetic, target)


base.instrument = instrument
base.calibrate = calibrate
base.CASES = {"friend": "KinUITests/KinUITests/testImportReviewRetainsFailedEditsAndAccessibilityHelpersWrap"}
base.PATTERNS["geometry"] = re.compile(r"KIN_GEOMETRY target=(friend|clear|review) ms=([0-9]{1,16})")
base.PATTERNS["observe"] = re.compile(r"KIN_OBSERVE stage=(immediate|later) value=(on|off|unknown) ms=([0-9]{1,16})")


def failure_category(text):
    if isinstance(text, str) and "Timed out while synthesizing event" in text:
        return "event_synthesis_timeout"
    if isinstance(text, str) and "XCTAssertEqual failed" in text:
        return "equality_assertion_failure"
    return original_failure_category(text)


base.failure_category = failure_category

if __name__ == "__main__":
    try:
        sys.exit(base.run_diagnostic("friend"))
    except Exception as exc:
        print("Synthetic diagnostic incomplete:", type(exc).__name__, file=sys.stderr)
        sys.exit(1)
