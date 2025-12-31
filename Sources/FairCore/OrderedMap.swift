// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// A dictionary-like collection that maintains the insertion order of its keys.
///
/// The primary purpose of this type is to serve as an encodable/decodable property container that will
/// retain the declared ordering the the serialized elements. For that reason, `K` will typically be a `String`.
/// Encoding will always use the stringified form of `K` as a dictionary key.
public struct OrderedMap<K: Hashable, T> {
    public private(set) var keys: [K] = []
    public private(set) var dict: [K: T] = [:]

    /// Creates an empty OrderedMap
    public init() {}

    /// Creates an OrderedMap from a sequence of key-value pairs
    public init<S: Sequence>(_ keysAndValues: S) where S.Element == (K, T) {
        for (key, value) in keysAndValues {
            self[key] = value
        }
    }

    /// The number of key-value pairs in the map
    public var count: Int {
        keys.count
    }

    /// Whether the map is empty
    public var isEmpty: Bool {
        keys.isEmpty
    }

    /// An array of all keys in insertion order
    public var orderedKeys: [K] {
        keys
    }

    public var values: [T] {
        self.map(\.value)
    }

    /// Accesses the value associated with the given key
    public subscript(key: K) -> T? {
        get {
            dict[key]
        }
        set {
            if let newValue = newValue {
                if dict[key] == nil {
                    keys.append(key)
                }
                dict[key] = newValue
            } else {
                if let index = keys.firstIndex(of: key) {
                    keys.remove(at: index)
                }
                dict.removeValue(forKey: key)
            }
        }
    }

    /// Updates the value for the given key, or adds a new key-value pair
    @discardableResult
    public mutating func updateValue(_ value: T, forKey key: K) -> T? {
        let oldValue = dict[key]
        if oldValue == nil {
            keys.append(key)
        }
        dict[key] = value
        return oldValue
    }

    /// Removes the value for the given key
    @discardableResult
    public mutating func removeValue(forKey key: K) -> T? {
        guard let value = dict.removeValue(forKey: key) else {
            return nil
        }
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
        }
        return value
    }

    /// Removes all key-value pairs
    public mutating func removeAll() {
        keys.removeAll()
        dict.removeAll()
    }

    public func mapValues<U>(_ transform: (T) throws -> U) rethrows -> OrderedMap<K, U> {
        var dict = OrderedMap<K, U>()
        for (key, value) in self {
            dict[key] = try transform(value)
        }
        return dict
    }
}

extension OrderedMap: Sendable where K: Sendable, T: Sendable {
}

// MARK: - ExpressibleByDictionaryLiteral

extension OrderedMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (K, T)...) {
        self.init(elements)
    }
}

// MARK: - Sequence

extension OrderedMap: Sequence {
    public func makeIterator() -> Iterator {
        Iterator(keys: keys, dict: dict)
    }

    public struct Iterator: IteratorProtocol {
        private let keys: [K]
        private let dict: [K: T]
        private var index = 0

        init(keys: [K], dict: [K: T]) {
            self.keys = keys
            self.dict = dict
        }

        public mutating func next() -> (key: K, value: T)? {
            guard index < keys.count else { return nil }
            let key = keys[index]
            index += 1
            guard let value = dict[key] else { return nil }
            return (key, value)
        }
    }
}

// MARK: - Collection

extension OrderedMap: Collection {
    public typealias Index = Int

    public var startIndex: Int { 0 }
    public var endIndex: Int { keys.count }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public subscript(position: Int) -> (key: K, value: T) {
        let key = keys[position]
        let value = dict[key]!
        return (key, value)
    }
}

// MARK: - Equatable

extension OrderedMap: Equatable where T: Equatable {
    public static func == (lhs: OrderedMap<K, T>, rhs: OrderedMap<K, T>) -> Bool {
        lhs.keys == rhs.keys && lhs.dict == rhs.dict
    }
}

// MARK: - Hashable

extension OrderedMap: Hashable where K: Hashable, T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(keys)
        hasher.combine(dict)
    }
}

// MARK: - Encodable

extension OrderedMap: Encodable where T: Encodable, K: CustomStringConvertible, K: ExpressibleByStringLiteral, K.StringLiteralType: StringProtocol {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey<K>.self)
        for key in keys {
            let codingKey = StringCodingKey(rawValue: key)
            try container.encode(dict[key], forKey: codingKey)
        }
    }
}

// MARK: - Decodable

extension OrderedMap: Decodable where K: CustomStringConvertible, K: ExpressibleByStringLiteral, K.StringLiteralType: StringProtocol, T: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey<K>.self)
        self.init()
        for key in container.allKeys {
            let value = try container.decode(T.self, forKey: key)
            self[key.rawValue] = value
        }
    }
}

// Helper type for dynamic string keys in Codable
private struct StringCodingKey<T: CustomStringConvertible & ExpressibleByStringLiteral>: RawRepresentable, CodingKey where T.StringLiteralType: StringProtocol {
    public var rawValue: T

    public init(stringValue: String) {
        self.rawValue = T(stringLiteral: T.StringLiteralType(stringLiteral: stringValue))
    }

    public init(rawValue: T) {
        self.rawValue = rawValue
    }

    public init?(intValue: Int) {
        return nil
    }

    public var intValue: Int? {
        nil
    }

    public var stringValue: String {
        rawValue.description
    }
}
