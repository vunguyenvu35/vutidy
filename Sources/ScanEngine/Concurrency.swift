import Foundation

public enum Concurrent {
    /// Map song song có giới hạn số task để không làm nghẽn I/O.
    public static func map<T: Sendable, R: Sendable>(_ input: [T], limit: Int = max(4, ProcessInfo.processInfo.activeProcessorCount),
                                                     _ transform: @escaping @Sendable (T) -> R) async -> [R] {
        await withTaskGroup(of: (Int, R).self) { group in
            var results = [R?](repeating: nil, count: input.count)
            var next = 0
            func feed(_ g: inout TaskGroup<(Int, R)>) {
                guard next < input.count else { return }
                let i = next; next += 1
                let v = input[i]
                g.addTask { (i, transform(v)) }
            }
            for _ in 0..<min(limit, input.count) { feed(&group) }
            for await (i, r) in group { results[i] = r; feed(&group) }
            return results.compactMap { $0 }
        }
    }
}
