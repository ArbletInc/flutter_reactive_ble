func id<T>(_ some: T) -> T {
    return some
}

func const<T, U>(_ value: U) -> (T) -> U {
    return { (_: T) -> U in value }
}

func const<U>(_ value: U) -> () -> U {
    return { () -> U in value }
}

extension Array {

    /// Returns the element at `index`, or nil instead of trapping when the index is out of range.
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
