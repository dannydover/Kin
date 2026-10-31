import importlib.util
import pathlib
import unittest

here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("probe", here / "diagnose-contact-toggle.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class TraceTests(unittest.TestCase):
    def events(self, immediate="on", later=False):
        result = [
            {"kind": "probe", "fields": ["true"], "uptime_ms": 100},
            {"kind": "geometry", "fields": ["review"], "uptime_ms": 150},
            {"kind": "heartbeat", "fields": [], "uptime_ms": 950},
            {"kind": "mark", "fields": ["friend", "before"], "uptime_ms": 1000},
            {"kind": "observe", "fields": ["immediate", immediate], "uptime_ms": 1100},
            {"kind": "mark", "fields": ["friend", "after"], "uptime_ms": 1200},
            {"kind": "heartbeat", "fields": [], "uptime_ms": 1250},
        ]
        if later:
            result.append({"kind": "observe", "fields": ["later", "on"], "uptime_ms": 1150})
        return result

    def test_review_geometry_and_immediate_state_are_required(self):
        events = self.events()
        self.assertTrue(probe.calibrate(events, "friend"))
        self.assertFalse(probe.calibrate([e for e in events if e["kind"] != "geometry"], "friend"))
        self.assertFalse(probe.calibrate([e for e in events if e["kind"] != "observe"], "friend"))

    def test_failed_immediate_state_requires_later_observation(self):
        self.assertFalse(probe.calibrate(self.events("off"), "friend"))
        self.assertTrue(probe.calibrate(self.events("off", later=True), "friend"))

    def test_fixed_field_sanitizer_rejects_extra_data(self):
        accepted = probe.base.sanitize_event({"eventMessage": "KIN_OBSERVE stage=later value=on ms=123"})
        self.assertEqual(accepted["fields"], ["later", "on"])
        self.assertIsNone(probe.base.sanitize_event({"eventMessage": "KIN_OBSERVE stage=later value=on ms=123 private"}))

    def test_failure_categories_are_allowlisted(self):
        self.assertEqual(probe.failure_category("Failed to synthesize event: Timed out while synthesizing event."), "event_synthesis_timeout")
        self.assertEqual(probe.failure_category("XCTAssertEqual failed: synthetic"), "equality_assertion_failure")


if __name__ == "__main__":
    unittest.main()
