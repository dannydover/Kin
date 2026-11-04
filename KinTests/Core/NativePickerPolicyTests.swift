import Foundation
import CoreGraphics
import Testing
#if SWIFT_PACKAGE
import SyntheticContactsTestSupport
#endif

@Suite("Native picker test policy") struct NativePickerPolicyTests {
    @Test("Synthetic card resolution rejects absence and ambiguity")
    func cards() {
        #expect(syntheticCardResolution(0) == .absent)
        #expect(syntheticCardResolution(1) == .unique)
        #expect(syntheticCardResolution(2) == .ambiguous)
        #expect(syntheticCardResolution(20) == .ambiguous)
    }

    @Test("Form visibility rejects empty and clipped frames")
    func frames() {
        #expect(preciseFormFrameIsVisible(CGRect(x: 1,y: 145,width: 100,height: 40), lowerBound: 145, upperBound: 500))
        #expect(!preciseFormFrameIsVisible(CGRect(x: 1,y: 145,width: 0,height: 40), lowerBound: 145, upperBound: 500))
        #expect(!preciseFormFrameIsVisible(CGRect(x: 1,y: 145,width: 100,height: 0), lowerBound: 145, upperBound: 500))
        #expect(!preciseFormFrameIsVisible(CGRect(x: 1,y: 144,width: 100,height: 40), lowerBound: 145, upperBound: 500))
        #expect(!preciseFormFrameIsVisible(CGRect(x: 1,y: 480,width: 100,height: 21), lowerBound: 145, upperBound: 500))
    }

    @Test("Reveal needs a unique stable target and observed movement")
    func reveal() {
        let deadline = NativeContactRevealDeadline(start: 100, timeout: 10)
        #expect(deadline.remaining(now: 103) == 7)
        #expect(deadline.remaining(now: 110) == 0)
        #expect(deadline.remaining(now: 111) == 0)
        var policy = NativeContactRevealPolicy()
        let offscreen = CGRect(x: 20,y: 900,width: 200,height: 50)
        let moved = CGRect(x: 20,y: 800,width: 200,height: 50)
        let visible = CGRect(x: 20,y: 300,width: 200,height: 50)
        func observe(_ count: Int, _ visibleCount: Int, _ frame: CGRect?, _ sole: CGRect?, _ now: TimeInterval) -> NativeContactRevealDecision {
            policy.observe(candidateCount: count, visibleCount: visibleCount, visibleFrame: frame, soleFrame: sole, lowerBound: 700, now: now)
        }
        #expect(observe(0,0,nil,nil,0) == .wait)
        #expect(observe(2,0,nil,nil,0) == .wait)
        #expect(observe(1,0,nil,offscreen,0) == .scrollUp)
        policy.didScroll(from: offscreen)
        #expect(observe(1,0,nil,offscreen,0.1) == .wait)
        #expect(observe(1,0,nil,moved,0.2) == .scrollUp)
        #expect(observe(1,1,visible,visible,0.3) == .wait)
        #expect(observe(1,1,visible,visible,1.2) == .wait)
        #expect(observe(1,1,visible,visible,1.4) == .select)
        #expect(observe(2,2,nil,nil,1.5) == .wait)
        for _ in 1..<16 { policy.didScroll(from: offscreen) }
        #expect(policy.scrolls == 16)
        #expect(observe(1,0,nil,moved,2) == .wait)
    }
}
