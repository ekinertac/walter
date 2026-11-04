/// Keeps presentation objects (not result models/actions) across query changes.
/// Callers clear and hide retired views. Only a bounded number of idle slots is
/// retained; an unusually large active theme list can still be displayed fully.
final class ReusableResultPool<Element> {
    private var slots: [Element] = []
    private var activeCount = 0
    private let retainedLimit: Int

    init(retainedLimit: Int) {
        precondition(retainedLimit >= 0)
        self.retainedLimit = retainedLimit
    }

    func prewarm(count: Int, make: () -> Element) {
        precondition(count >= 0 && count <= retainedLimit)
        while slots.count < count { slots.append(make()) }
    }

    func resize(count: Int, make: () -> Element, retire: (Element) -> Void,
                discard: (Element) -> Void) -> [Element] {
        precondition(count >= 0)
        if count < activeCount {
            for slot in slots[count..<activeCount] { retire(slot) }
        }
        let keep = max(count, retainedLimit)
        if slots.count > keep {
            for slot in slots[keep...] { discard(slot) }
            slots.removeLast(slots.count - keep)
        }
        while slots.count < count { slots.append(make()) }
        activeCount = count
        return Array(slots.prefix(count))
    }
}
