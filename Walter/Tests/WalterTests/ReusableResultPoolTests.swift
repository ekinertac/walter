import Testing
@testable import Walter

// Pure objects only: no NSViews, windows, application lifecycle, or OS state.
private final class FixtureSlot {
    let id: Int
    var text: String?
    var action: (() -> Int)?
    init(_ id: Int) { self.id = id }
    func clear() { text = nil; action = nil }
}

@Suite("Bounded reusable presentation slots (no GUI)")
struct ReusableResultPoolTests {
    @Test func prewarmedSlotsSurviveEmptyAndClearOldContentAndActions() {
        let pool = ReusableResultPool<FixtureSlot>(retainedLimit: 3)
        var created = 0
        func make() -> FixtureSlot { defer { created += 1 }; return FixtureSlot(created) }
        pool.prewarm(count: 3, make: make)
        let first = pool.resize(count: 3, make: make, retire: { $0.clear() }, discard: { _ in })
        for (i, slot) in first.enumerated() { slot.text = "Fixture"; slot.action = { i } }
        #expect(pool.resize(count: 0, make: make, retire: { $0.clear() }, discard: { _ in }).isEmpty)
        #expect(first.allSatisfy { $0.text == nil && $0.action == nil })
        let next = pool.resize(count: 3, make: make, retire: { $0.clear() }, discard: { _ in })
        for (i, slot) in next.enumerated() { slot.action = { i + 10 } }
        #expect(created == 3)
        #expect(zip(first, next).allSatisfy { $0 === $1 })
        #expect(next.map { $0.action?() } == [10, 11, 12])
    }

    @Test func largeActiveListIsNotCappedButIdleRetentionIsBounded() {
        let pool = ReusableResultPool<FixtureSlot>(retainedLimit: 2)
        var created = 0
        var retired: [Int] = []
        var discarded: [Int] = []
        func make() -> FixtureSlot { defer { created += 1 }; return FixtureSlot(created) }
        #expect(pool.resize(count: 5, make: make, retire: { retired.append($0.id) }, discard: { discarded.append($0.id) }).count == 5)
        _ = pool.resize(count: 1, make: make, retire: { retired.append($0.id) }, discard: { discarded.append($0.id) })
        #expect(retired == [1, 2, 3, 4])
        #expect(discarded == [2, 3, 4])
        let restored = pool.resize(count: 2, make: make, retire: { _ in }, discard: { _ in })
        #expect(restored.map(\.id) == [0, 1])
        #expect(created == 5)
        let expanded = pool.resize(count: 3, make: make, retire: { _ in }, discard: { _ in })
        #expect(expanded.map(\.id) == [0, 1, 5])
    }

    @Test func sameCountDoesNotAllocateRetireOrDiscard() {
        let pool = ReusableResultPool<FixtureSlot>(retainedLimit: 2)
        var created = 0
        var retired = 0
        var discarded = 0
        func make() -> FixtureSlot { defer { created += 1 }; return FixtureSlot(created) }
        let first = pool.resize(count: 2, make: make, retire: { _ in retired += 1 }, discard: { _ in discarded += 1 })
        let second = pool.resize(count: 2, make: make, retire: { _ in retired += 1 }, discard: { _ in discarded += 1 })
        #expect(created == 2 && retired == 0 && discarded == 0)
        #expect(zip(first, second).allSatisfy { $0 === $1 })
    }

    @Test func zeroRetentionDiscardsInactiveObjectsButAllowsActiveOnes() {
        let pool = ReusableResultPool<FixtureSlot>(retainedLimit: 0)
        var created = 0
        var discarded = 0
        func make() -> FixtureSlot { defer { created += 1 }; return FixtureSlot(created) }
        pool.prewarm(count: 0, make: make)
        #expect(pool.resize(count: 0, make: make, retire: { _ in }, discard: { _ in }).isEmpty)
        #expect(created == 0)
        #expect(pool.resize(count: 2, make: make, retire: { _ in }, discard: { _ in }).count == 2)
        _ = pool.resize(count: 0, make: make, retire: { _ in }, discard: { _ in discarded += 1 })
        #expect(discarded == 2)
        _ = pool.resize(count: 2, make: make, retire: { _ in }, discard: { _ in })
        #expect(created == 4)
    }
}
