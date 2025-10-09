import Swift
import struct Foundation.IndexPath

/// The mode for enumerating or searching in a tree
public enum TreeTraversal {
    case breadthFirst
    case depthFirst
}

/// An iterator over tree nodes.
public typealias TreeNodeIterator = AnyIterator

/// A enumerated sequence of tree node indices and values. Analagous to `EnumeratedSequence`
public typealias TreeEnumeration<C: Collection> = AnySequence<(indices: [C.Index], element: C.Element)>
public typealias TreeNodeSequence<Children : Collection> = LazyMapSequence<TreeEnumeration<Children>, Children.Element>
public typealias TreeIndexSequence<Children : Collection> = LazyMapSequence<TreeEnumeration<Children>, IndexPath>

public protocol TreeRoot {
}

public extension TreeRoot {
    /// Provides a depth-first iterator for the given keypath
    @inlinable subscript<Children: Sequence>(depthFirst children: @escaping (Self) -> (Children)) -> TreeNodeIterator<Self> where Children.Element == Self {
        CollectionOfOne(self).depthFirstIterator(children: children)
    }

    /// Provides a breadth-first iterator for the given keypath
    @inlinable subscript<Children: Sequence>(breadthFirst children: @escaping (Self) -> (Children)) -> TreeNodeIterator<Self> where Children.Element == Self {
        CollectionOfOne(self).breadthFirstIterator(children: children)
    }
}

public extension Collection {
    /// Returns the head element and tail elements of this collection
    @inlinable var headAndTail: (head: Element, tail: SubSequence)? {
        guard let head = self.first else { return nil }
        return (head, dropFirst())
    }
}

public extension Sequence {
    /// Returns the head element and tail elements of this sequence
    /// - See Also: https://oleb.net/2018/sequence-head-tail/
    @inlinable var headAndTail: (head: Element, tail: DropWhileSequence<Self>)? {
        var first: Element? = nil

        // note that since the `drop` closure is not escaping, we are guaranteed that it will run immediately
        let tail = drop(while: { element in
            if first == nil {
                first = element
                return true
            } else {
                return false
            }
        })
        guard let head = first else {
            return nil
        }
        return (head, tail)
    }
}


/// Utility functions for operating on trees of elements
public enum TreeEnumerations {

    /// Recursively enumerates the elements of the given tree, returning the elements and their corresponding `IndexPath`
    /// - Parameters:
    ///   - parent: the root node the traverse
    ///   - traverse: how to traverse the tree, either `.depthFirst` or `.breadthFirst`
    ///   - maxDepth: the maximum depth of the tree to traverse
    ///   - children: the callback to obtain the children
    /// - Returns: the enumerated sequence of `IndexPath` and child elements
    /// - Note: this is analagous to `Sequence.enumerated`
    /// - Note: breadth-first enumeration is around 5 times slower than depth-first enumeration
    @inlinable public static func enumerated<Parent, Children : Collection>(_ roots: [Parent], traverse: TreeTraversal, maxDepth: UInt = .max, children: @escaping (Parent) -> (Children)) -> TreeEnumeration<Children> where Children.Element == Parent {
        roots.map({ ([], $0) }).flatTree(traverse: traverse) { parentIndices, parent in
            children(parent)
                .zippedWithIndices
                .lazy
                .filter { _ in
                    parentIndices.count < maxDepth // index count is the tree depth
                }
                .map { (childIndex, value) in
                    (parentIndices + [childIndex], value)
                }
        }
    }

    /// Returns all the node elements of the tree in the specified traversal order.
    /// - Parameters:
    ///   - root: the root node
    ///   - depthFirst: whether to traverse in breadth-first or depth-first order
    ///   - maxDepth: the maximum depth to traverse
    ///   - children: a closure that returns the children for the item
    /// - Returns: a lazy sequence of node elements of the tree, including the `root`
    @inlinable public static func nodes<Parent, Children : Collection>(_ root: Parent, traverse: TreeTraversal, maxDepth: UInt = .max, children: @escaping (Parent) -> (Children)) -> TreeNodeSequence<Children> where Children.Element == Parent, Children.Index == Int {
        TreeEnumerations.enumerated([root], traverse: traverse, maxDepth: maxDepth, children: children).lazy.map(\.element)
    }

    /// Returns the indices for the elements of this tree as `IndexPath` elements
    /// - Parameters:
    ///   - root: the root node
    ///   - depthFirst: whether to traverse in breadth-first or depth-first order
    ///   - maxDepth: the maximum depth to traverse
    ///   - children: a closure that returns the children for the item
    /// - Returns: a last sequence of indices for the trees
    @inlinable public static func indices<Parent, Children : Collection>(_ root: Parent, traverse: TreeTraversal, maxDepth: UInt = .max, children: @escaping (Parent) -> (Children)) -> TreeIndexSequence<Children> where Children.Element == Parent, Children.Index == Int {
        TreeEnumerations.enumerated([root], traverse: traverse, maxDepth: maxDepth, children: children).lazy.map(\.indices).map(IndexPath.init(indexes:))
    }

    /// Traverses the hierarchy of nodes along the collection of indices
    /// - Parameters:
    ///   - root: the root node
    ///   - indices: the collection of incides to traverse (e.g., an `IndexPath`)
    ///   - children: the function or keyPath to fetch the children from the parent
    /// - Returns: the element in the tree at the index path collection
    @inlinable public static func traverse<Parent, Indices: Sequence, Children : Collection>(from root: Parent, at indices: Indices, children: (Parent) -> (Children)) -> Children.Element where Indices.Element == Children.Index, Children.Element == Parent {
        var node = root
        for idx in indices {
            node = children(node)[idx]
        }
        return node
    }

    /// Safe form of `verse`, returning `nil` if the given index does not exist.
    @inlinable public static func query<Parent, Indices: Sequence, Children : Collection>(from root: Parent, at indices: Indices, children: (Parent) -> (Children)) -> Children.Element? where Indices.Element == Children.Index, Children.Element == Parent {
        var node = root
        for idx in indices {
            let nkp = children(node)
            guard nkp.indices.contains(idx) else { return nil }
            node = nkp[idx]
        }
        return node
    }

    /// For a tree type with a given path to its children, replaces the `element` to the given index path and returns the replaced element
    /// - Parameters:
    ///   - element: the node to assign to the index path
    ///   - tree: the root of the tree to assign
    ///   - indices: the assignation path (e.g., an `IndexPath`)
    ///   - children: the writable key path that will perform the assignment
    /// - Returns: the element of the tree that was replaced
    @inlinable @discardableResult public static func place<Indices: Sequence, Children: MutableCollection>(_ element: Children.Element, into tree: inout Children.Element, at indices: Indices, children keyPath: WritableKeyPath<Children.Element, Children>) -> Children.Element where Indices.Element == Children.Index {
        if let (headIndex, trailIndices) = indices.headAndTail {
            return TreeEnumerations.place(element, into: &tree[keyPath: keyPath][headIndex], at: trailIndices, children: keyPath)
        } else {
            defer { tree = element }
            return tree // return the old element
        }
    }
}

public extension KeyPath where Value: Sequence, Value.Element == Root {
    /// The total count of all the items in this tree
    @inlinable func treeCount(for root: Root) -> Int {
        return root[keyPath: self].reduce(1, { $0 + treeCount(for: $1) })
    }
}

extension KeyPath where Value: Collection, Value.Element == Root, Value.Index == Int {

    /// Similar to `treeverse`, but returns a collection of all the items along the indices
    @usableFromInline internal func gather<I: Sequence>(from root: Root, indices: I, deepestFirst: Bool) -> [Value.Element] where I.Element == Value.Index {
        var elements: [Value.Element] = []
        elements.reserveCapacity(indices.underestimatedCount + 1)
        elements.append(root)

        var node: Root = root
        for idx in indices {
            node = node[keyPath: self][idx]
            if deepestFirst {
                elements.insert(node, at: 0)
            } else {
                elements.append(node)
            }
        }
        return elements
    }

    /// For the given tree structure, returns the next index path for the given index in a depth-first traversal.
    @usableFromInline func nextDepthIndexPath(for root: Root, after index: [Value.Index]) -> [Value.Index]? {
        var indices = index
        for (idx, element) in zip([nil] + index.reversed(), self.gather(from: root, indices: indices, deepestFirst: true)) {
            let children = element[keyPath: self]
            if let idx = idx {
                if idx < children.index(children.endIndex, offsetBy: -1) {
                    return indices + [children.index(idx, offsetBy: +1)] // return the index of the next child over
                }
            } else { // a null index means it is the terminal element, in which case we return the first child index (if it has any children)
                if !children.isEmpty {
                    return indices + [children.startIndex]
                }
            }
            if indices.isEmpty {
                return nil // we're all out of indexes, so we're at the end…
            } else {
                indices.removeLast() // …otherwise keep looking for the next index up the tree
            }
        }

        return nil
    }
}

public extension WritableKeyPath where Value: MutableCollection & RangeReplaceableCollection, Value.Element == Root {
    /// For a tree type with a given path to its children, remove the `element` at the given index path;
    /// note that attempting to remove the root level of the tree will be a no-op, since a
    /// tree must always have a root node.
    @inlinable @discardableResult func treeRemove<I: Collection>(elements removeIndices: Set<I>, from root: inout Root) -> [I: Value.Element?] where I.Element == Value.Index, I : Comparable {
        // delete in reverse depth-first so we don't try to delete children after their parents
        let indices = removeIndices.sorted(by: >)
        // dbg("removing", indices)
        return Dictionary(indices.map({ ($0, treeRemoveElement(at: $0, from: &root)) }), uniquingKeysWith: { (first, _) in first })
    }

    @usableFromInline @discardableResult internal func treeRemoveElement<I: Collection>(at indices: I, from root: inout Root) -> Value.Element? where I.Element == Value.Index {
        guard let first = indices.first else { return .none }
        if indices.count > 1 {
            return treeRemoveElement(at: indices.dropFirst(), from: &root[keyPath: self][first])
        } else {
            return root[keyPath: self].remove(at: first)
        }
    }
}


public extension KeyPath where Value: BidirectionalCollection, Value.Element == Root, Value.Index == Int {
    /// Returns the array of indexes for the last element (depth-first) of the traversal of the given tree
    @inlinable func lastDepthIndexPath(for root: Root) -> [Value.Index] {
        var indices: [Value.Index] = []
        var item = root // start with the root…
        repeat {
            let children = item[keyPath: self]
            if children.isEmpty { return indices }
            let idx = children.index(before: children.endIndex)
            indices.append(idx)
            item = children[idx] // …and traverse down to the final item
        } while (true) // eventually we should hit the end of the tree (unless it has a cycle)
    }

    /// For the given tree structure, returns the prior index path for the given index in a depth-first traversal.
    @inlinable func priorDepthIndexPath(for root: Root, before i: [Value.Index]) -> [Value.Index]? {
        guard let last = i.last else {
            return nil // root index has no prior index
        }

        let children = root[keyPath: self]

        // decrement or drop last element: [0, 0, 1] -> [0, 0, 0] & [0, 0, 0] -> [0, 0]
        // this path is guaranteed to be valid, altough it is not yet the end index
        if last <= children.startIndex {
            return i.dropLast() // move up one
        } else {
            let previousIndex = i.dropLast() + [children.index(last, offsetBy: -1)]
            // now append the lastIndex to the previous index and get the final index of the child
            return previousIndex + lastDepthIndexPath(for: TreeEnumerations.traverse(from: root, at: previousIndex, children: { $0[keyPath: self] }))
        }
    }
}

public protocol TreeOf {
    /// The type of this tree; we only need this to be able to adopt the protocol by non-final classes, else:
    /// Protocol 'TreeOf' requirement 'childrenKeyPath' cannot be satisfied by a non-final class ('NSTreeNode') because it uses 'Self' in a non-parameter, non-result type position
    associatedtype TreeType
    associatedtype ChildType
    static var childrenKeyPath: WritableKeyPath<TreeType, [ChildType]> { get }
}

/// A `TreeOf` sub-protocol that implements a BiDirectional collection
public protocol TreeOfElements : TreeOf, BidirectionalCollection where TreeType == Self, Index == IndexPath {
}

/// A TreeOfSelf is an instance that contains itself as a collection of children.
/// Children are accessed through the `childrenKeyPath` mathod. Collection indexing
/// is done based on the `IndexPath` structure.
///
/// Note that we don't implement RangeReplaceableCollection because we don't want to
/// require a default initializer, and it also isn't obvious what should happen with
/// replacements that span multiple tree levels, like:
/// replaceRange([0]...[1,1,1,1], [])
public protocol TreeOfSelf : TreeOfElements, MutableCollection where ChildType == Self {
}

public extension TreeOfSelf {
    /// `treeChildren` simply queries the keyPath to the local children
    @inlinable var treeChildren: [ChildType] {
        get { return self[keyPath: Self.childrenKeyPath] }
        set { self[keyPath: Self.childrenKeyPath] = newValue }
    }

    /// Inserts the given element before the specified index;
    /// the signature matches that in RangeReplaceableCollection
    @inlinable mutating func insert(_ newElement: ChildType, at i: IndexPath) {
        guard let firstIndex = i.first else { return self = newElement }
        return i.count == 1
            ? self[keyPath: Self.childrenKeyPath].insert(newElement, at: firstIndex)
            : self[keyPath: Self.childrenKeyPath][firstIndex].insert(newElement, at: i.dropFirst())
    }

    /// Removes the given elements at the specified indices.
    @inlinable mutating func remove(elements i: Set<IndexPath>) {
        Self.childrenKeyPath.treeRemove(elements: i, from: &self)
    }

    /// Removes the given element at the specified index.
    @inlinable mutating func remove(at i: IndexPath) {
        remove(elements: [i])
    }

}

public extension TreeOfSelf {
    /// The total number of items in this tree; this may be faster than `count` because it doesn't need
    /// to build up a list of all the indices internally, but rather just perform a recursive
    /// count of all the subtrees.
    var treeCount: Int {
        // BidirectionalCollection gives us `count` for free, but it is based on incrementing
        // indices, which is very slow for trees; we can calculate it much faster (albeit recursively)
        return Self.childrenKeyPath.treeCount(for: self)
    }

    @inlinable var startIndex: Index {
        return [] // an empty index maps to this tree
    }

    @inlinable subscript(position: IndexPath) -> Self {
        get { TreeEnumerations.traverse(from: self, at: position, children: { $0[keyPath: Self.childrenKeyPath] }) }
        set { TreeEnumerations.place(newValue, into: &self, at: position, children: Self.childrenKeyPath) }
    }
}

/// `TreeOf` subprotocol that defines how the tree will be interpreted as a collection.
///
/// An example implementation that permits NSView to conform can be done with the simple extension:
///
///      `extension NSView : DepthFirstTreeOf { public static var childrenKeyPath: WritableKeyPath<NSView, [NSView]> = \NSView.subviews }`
///
///
/// TODO: rather than having depth-/breadth-first behavior as a protocol implementation,
/// we should instead have `depthFirstView` and `breadthFirstView` vars on `TreeOfSelf`,
/// which would behave similarly to String's `utf8` and `utf16` views of the string.
public protocol DepthFirstTreeOf : TreeOfElements {
}

/// A depth-first tree is a tree that iterates elements depth-first.
/// The `endIndex` for a depth-first tree is the final index with an additional child node.
/// This is merely a marker protocol to indicate how traversal behavior should perform;
/// an alternative `BreadthFirstTreeOfSelf` could also be implemented with the same
public protocol DepthFirstTreeOfSelf : TreeOfSelf, DepthFirstTreeOf {
}


/// Depth-first implementation of the index members that allow the tree to conform to `BidirectionalCollection`.
public extension DepthFirstTreeOf where TreeType == Self, ChildType == Self {
    /// The end index if the last valid index with a [-1] at the end
    @inlinable var endIndex: Index {
        return Index(indexes: Self.childrenKeyPath.lastDepthIndexPath(for: self) + [-1]) // a trailing -1 marks the end index
    }

    @inlinable func index(after i: IndexPath) -> IndexPath {
        return Self.childrenKeyPath.nextDepthIndexPath(for: self, after: i.map({ $0 })).flatMap(Index.init(indexes:)) ?? self.endIndex
    }

    @inlinable func index(before i: IndexPath) -> IndexPath {
        return Self.childrenKeyPath.priorDepthIndexPath(for: self, before: i.map({ $0 })).flatMap(Index.init(indexes:)) ?? self.startIndex
    }
}

public extension Sequence {
    typealias TreeSequence = AnySequence<Element>

    /// Returns a sequence that flattens a tree using either depth-first or breadth-first traversal.
    /// - Parameters:
    ///   - traverse: the method of traversal
    ///   - children: the path from the root element
    /// - Returns: the sequence to iterate over
    @inlinable func flatTree<Children: Sequence>(traverse: TreeTraversal, children: @escaping (Element) -> (Children)) -> TreeSequence where Children.Element == Element {
        switch traverse {
        case .depthFirst: return TreeSequence { depthFirstIterator(children: children) }
        case .breadthFirst: return TreeSequence { breadthFirstIterator(children: children) }
        }
    }

    /// Returns a depth-first iterator over all the elements in the sequence.
    @inlinable func depthFirstIterator<Children: Sequence>(children: @escaping (Element) -> (Children)) -> TreeSequence.Iterator where Children.Element == Element {
        var iterator = self.makeIterator()
        var childIterator: TreeSequence.Iterator?
        return TreeSequence.Iterator {
            if let childIterator = childIterator, let nextChild = childIterator.next() {
                return nextChild
            } else if let next = iterator.next() {
                childIterator = children(next).depthFirstIterator(children: children).makeIterator()
                return next
            } else {
                return nil
            }
        }
    }

    /// Returns a breadth-first iterator over all the elements in the sequence.
    @inlinable func breadthFirstIterator<Children: Sequence>(children: @escaping (Element) -> (Children)) -> TreeSequence.Iterator where Children.Element == Element {
        var iterator: TreeSequence.Iterator? = TreeSequence.Iterator(self.makeIterator())
        var queue: ArraySlice<TreeSequence.Iterator> = []
        return TreeSequence.Iterator {
            while let it = iterator {
                if let next = it.next() {
                    queue.append(TreeSequence.Iterator(children(next).makeIterator()))
                    return next
                }
                iterator = queue.popFirst()
            }
            return nil
        }
    }
}

public extension Collection {
    /// Zips the elements of this collection with its indices
    @inlinable var zippedWithIndices: Zip2Sequence<Self.Indices, Self> {
        zip(self.indices, self)
    }
}
