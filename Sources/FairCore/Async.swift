import Foundation


// MARK: async conveniences

extension Sequence {
    /// Variant `Sequence.reduce` that accepts an `async` closure
    @inlinable public func reduceAsync<Result>(into initialResult: Result, _ updateAccumulatingResult: (inout Result, Self.Element) async throws -> ()) async rethrows -> Result {
        var result = initialResult
        for element in self {
            try await updateAccumulatingResult(&result, element)
        }
        return result
    }

    /// Variant `Sequence.map` that accepts an `async` closure
    @inlinable public func mapAsync<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        try await reduceAsync(into: [T]()) { result, element in
            try await result.append(transform(element))
        }
    }

    /// Variant `Sequence.flatMap` that accepts an `async` closure
    @inlinable public func flatMapAsync<T>(_ transform: (Element) async throws -> [T]) async rethrows -> [T] {
        try await mapAsync(transform).joined().array()
    }

    /// Variant `Sequence.filter` that accepts an `async` closure
    @inlinable public func filterAsync(_ filter: (Element) async throws -> Bool) async rethrows -> [Element] {
        try await mapAsync { element in
            (element: element, result: try await filter(element))
        }
        .filter(\.result)
        .map(\.element)
    }
}


extension Sequence {
    /// Creates a new Task with the specified priority and returns an `AsyncThrowingStream` mapping over each element.
    public func asyncMap<T>(priority: TaskPriority? = nil, _ block: @escaping (Element) async throws -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { c in
            Task(priority: priority) {
                do {
                    for item in self {
                        c.yield(try await block(item))
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
        }
    }

    /// Creates a new Task with the specified priority and returns an `AsyncThrowingStream` invoking the block with the initial element.
    public func asyncReduce<Result>(priority: TaskPriority? = nil, initialResult: Result?, _ nextPartialResult: @escaping (Element, Result?) async throws -> Result) -> AsyncThrowingStream<Result, Error> {
        AsyncThrowingStream { c in
            Task(priority: priority) {
                do {
                    var previousValue = initialResult
                    for item in self {
                        let value = try await nextPartialResult(item, previousValue)
                        c.yield(value)
                        previousValue = value
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
        }
    }

    /// Concurrently executes the given transformation, returning the results in the order of the sequence's elements
    @inlinable public func concurrentMap<T>(priority: TaskPriority? = nil, _ transform: @escaping (Element) async throws -> T) async rethrows -> [T] {
        try await mapAsync { element in
            Task(priority: priority) {
                try await transform(element)
            }
        }.mapAsync { task in
            try await task.value
        }
    }
}


actor AsyncBufferState<Input: Sendable, Output: Sendable> {
  enum TerminationState: Sendable, CustomStringConvertible {
    case running
    case baseFailure(Error) // An error from the base sequence has occurred. We need to process any buffered items before throwing the error. We can rely on it not emitting any more items.
    case baseTermination
    case terminal

    var description: String {
      switch self {
        case .running: return "running"
        case .baseFailure: return "base failure"
        case .baseTermination: return "base termination"
        case .terminal: return "terminal"
      }
    }
  }

  var pending = [UnsafeContinuation<Result<Output?, Error>, Never>]()
  var terminationState = TerminationState.running

  init() { }

  func drain<Buffer: AsyncBuffer>(buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    guard pending.count > 0 else {
      return
    }

    do {
      if let value = try await buffer.pop() {
        pending.removeFirst().resume(returning: .success(value))
      } else {
        switch terminationState {
          case .running:
            // There's no value to report, because it was probably grabbed by next() before we could grab it. The pending continuation was either resumed by next() directly, or will be by a future enqueued value or base termination/failure.
            break
          case .baseFailure(let error):
            // Now that there are no more items in the buffer, we can finally report the base sequence's error and enter terminal state.
            pending.removeFirst().resume(returning: .failure(error))
            self.terminate()
          case .terminal, .baseTermination:
            self.terminate()
        }
      }
    } catch {
      // Errors thrown by the buffer immediately terminate the sequence.
      pending.removeFirst().resume(returning: .failure(error))
      self.terminate()
    }
  }

  func enqueue<Buffer: AsyncBuffer>(_ item: Input, buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    await buffer.push(item)
    await drain(buffer: buffer)
  }

  func fail<Buffer: AsyncBuffer>(_ error: Error, buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    terminationState = .baseFailure(error)
    await drain(buffer: buffer)
  }

  func finish<Buffer: AsyncBuffer>(buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    if case .running = terminationState {
      terminationState = .baseTermination
    }
    await drain(buffer: buffer)
  }

  func terminate() {
    terminationState = .terminal
    let oldPending = pending
    pending = []
    for continuation in oldPending {
      continuation.resume(returning: .success(nil))
    }
  }

  func next<Buffer: AsyncBuffer>(buffer: Buffer) async throws -> Buffer.Output? where Buffer.Input == Input, Buffer.Output == Output {
    if case .terminal = terminationState {
      return nil
    }

    do {
      while let value = try await buffer.pop() {
        if let continuation = pending.first {
          pending.removeFirst()
          continuation.resume(returning: .success(value))
        } else {
          return value
        }
      }
    } catch {
      // Errors thrown by the buffer immediately terminate the sequence.
      self.terminate()
      throw error
    }

    switch terminationState {
      case .running:
        break
      case .baseFailure(let error):
        self.terminate()
        throw error
      case .baseTermination, .terminal:
        self.terminate()
        return nil
    }

    let result: Result<Output?, Error> = await withUnsafeContinuation { continuation in
      pending.append(continuation)
    }
    return try result._rethrowGet()
  }
}

/// An asynchronous buffer storage actor protocol used for buffering
/// elements to an `AsyncBufferSequence`.
@rethrows
public protocol AsyncBuffer: Actor {
  associatedtype Input: Sendable
  associatedtype Output: Sendable

  /// Push an element to enqueue to the buffer
  func push(_ element: Input) async

  /// Pop an element from the buffer.
  ///
  /// Implementors of `pop()` may throw. In cases where types
  /// throw from this function, that throwing behavior contributes to
  /// the rethrowing characteristics of `AsyncBufferSequence`.
  func pop() async throws -> Output?
}

/// A buffer that limits pushed items by a certain count.
public actor AsyncLimitBuffer<Element: Sendable>: AsyncBuffer {
  /// A policy for buffering elements to an `AsyncLimitBuffer`
  public enum Policy: Sendable {
    /// A policy for no bounding limit of pushed elements.
    case unbounded
    /// A policy for limiting to a specific number of oldest values.
    case bufferingOldest(Int)
    /// A policy for limiting to a specific number of newest values.
    case bufferingNewest(Int)
  }

  var buffer = [Element]()
  let policy: Policy

  init(policy: Policy) {
    // limits should always be greater than 0 items
    switch policy {
      case .bufferingNewest(let limit):
        precondition(limit > 0)
      case .bufferingOldest(let limit):
        precondition(limit > 0)
      default: break
    }
    self.policy = policy
  }

  /// Push an element to enqueue to the buffer.
  public func push(_ element: Element) async {
    switch policy {
    case .unbounded:
      buffer.append(element)
    case .bufferingOldest(let limit):
      if buffer.count < limit {
        buffer.append(element)
      }
    case .bufferingNewest(let limit):
      if buffer.count < limit {
        // there is space available
        buffer.append(element)
      } else {
        // no space is available and this should make some room
        buffer.removeFirst()
        buffer.append(element)
      }
    }
  }

  /// Pop an element from the buffer.
  public func pop() async -> Element? {
    guard buffer.count > 0 else {
      return nil
    }
    return buffer.removeFirst()
  }
}

extension AsyncSequence where Element: Sendable, Self: Sendable {
  /// Creates an asynchronous sequence that buffers elements using a buffer created from a supplied closure.
  ///
  /// Use the `buffer(_:)` method to account for `AsyncSequence` types that may produce elements faster
  /// than they are iterated. The `createBuffer` closure returns a backing buffer for storing elements and dealing with
  /// behavioral characteristics of the `buffer(_:)` algorithm.
  ///
  /// - Parameter createBuffer: A closure that constructs a new `AsyncBuffer` actor to store buffered values.
  /// - Returns: An asynchronous sequence that buffers elements using the specified `AsyncBuffer`.
  public func buffer<Buffer: AsyncBuffer>(_ createBuffer: @Sendable @escaping () -> Buffer) -> AsyncBufferSequence<Self, Buffer> where Buffer.Input == Element {
    AsyncBufferSequence(self, createBuffer: createBuffer)
  }

  /// Creates an asynchronous sequence that buffers elements using a specific policy to limit the number of
  /// elements that are buffered.
  ///
  /// - Parameter policy: A limiting policy behavior on the buffering behavior of the `AsyncBufferSequence`
  /// - Returns: An asynchronous sequence that buffers elements up to a given limit.
  public func buffer(policy limit: AsyncLimitBuffer<Element>.Policy) -> AsyncBufferSequence<Self, AsyncLimitBuffer<Element>> {
    buffer {
      AsyncLimitBuffer(policy: limit)
    }
  }
}

/// An `AsyncSequence` that buffers elements utilizing an `AsyncBuffer`.
public struct AsyncBufferSequence<Base: AsyncSequence & Sendable, Buffer: AsyncBuffer> where Base.Element == Buffer.Input {
  let base: Base
  let createBuffer: @Sendable () -> Buffer

  init(_ base: Base, createBuffer: @Sendable @escaping () -> Buffer) {
    self.base = base
    self.createBuffer = createBuffer
  }
}

extension AsyncBufferSequence: Sendable where Base: Sendable { }

extension AsyncBufferSequence: AsyncSequence {
  public typealias Element = Buffer.Output

  /// The iterator for a `AsyncBufferSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
    struct Active {
      var task: Task<Void, Never>?
      let buffer: Buffer
      let state: AsyncBufferState<Buffer.Input, Buffer.Output>

      init(_ base: Base, buffer: Buffer, state: AsyncBufferState<Buffer.Input, Buffer.Output>) {
        self.buffer = buffer
        self.state = state
        task = Task {
          var iter = base.makeAsyncIterator()
          do {
            while let item = try await iter.next() {
              await state.enqueue(item, buffer: buffer)
            }
            await state.finish(buffer: buffer)
          } catch {
            await state.fail(error, buffer: buffer)
          }
        }
      }

      func next() async rethrows -> Element? {
        let result: Result<Element?, Error> = await withTaskCancellationHandler {
          do {
            let value = try await state.next(buffer: buffer)
            return .success(value)
          } catch {
            task?.cancel()
            return .failure(error)
          }
        } onCancel: {
          task?.cancel()
        }
        return try result._rethrowGet()
      }
    }

    enum State {
      case idle(Base, @Sendable () -> Buffer)
      case active(Active)
    }

    var state: State

    init(_ base: Base, createBuffer: @Sendable @escaping () -> Buffer) {
      state = .idle(base, createBuffer)
    }

    public mutating func next() async rethrows -> Element? {
      switch state {
      case .idle(let base, let createBuffer):
        let bufferState = AsyncBufferState<Base.Element, Buffer.Output>()
        let buffer = Active(base, buffer: createBuffer(), state: bufferState)
        state = .active(buffer)
        return try await buffer.next()
      case .active(let buffer):
        return try await buffer.next()
      }
    }
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(base, createBuffer: createBuffer)
  }
}

/// An `AsyncIterator` that provides a convenient and high-performance implementation
/// of a common architecture for `AsyncSequence` of `UInt8`, otherwise known as byte streams.
///
/// Bytes are read into an internal buffer of `capacity` bytes via the
/// `readFunction`. Invoking `next()` returns bytes from the internal buffer until it's
/// empty, and then suspends and awaits another invocation of `readFunction` to
/// refill. If `readFunction` returns 0 (indicating nothing was read), `next()` will
/// return `nil` from then on. Cancellation is checked before each invocation of
/// `readFunction`, which means that many calls to `next()` will not check for
/// cancellation.
///
/// A typical use of `AsyncBufferedByteIterator` looks something like this:
///
///     struct AsyncBytes: AsyncSequence {
///       public typealias Element = UInt8
///       var handle: ReadableThing
///
///       internal init(_ readable: ReadableThing) {
///         handle = readable
///       }
///
///       public func makeAsyncIterator() -> AsyncBufferedByteIterator {
///         return AsyncBufferedByteIterator(capacity: 16384) { buffer in
///           // This runs once every 16384 invocations of next()
///           return try await handle.read(into: buffer)
///         }
///       }
///     }
///
///
public struct AsyncBufferedByteIterator: AsyncIteratorProtocol {
  public typealias Element = UInt8
  @usableFromInline var buffer: _AsyncBytesBuffer

  /// Creates an asynchronous buffered byte iterator with a specified capacity and read function.
  ///
  /// - Parameters:
  ///   - capacity: The maximum number of bytes that a single invocation of `readFunction` may produce.
  ///   This is the allocated capacity of the backing buffer for iteration; the value must be greater than 0.
  ///   - readFunction: The function for refilling the buffer.
  public init(
    capacity: Int,
    readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int
  ) {
    buffer = _AsyncBytesBuffer(capacity: capacity, readFunction: readFunction)
  }

  /// Reads a byte out of the buffer if available. When no bytes are available, this will trigger
  /// the read function to reload the buffer and then return the next byte from that buffer.
  @inlinable @inline(__always)
  public mutating func next() async throws -> UInt8? {
    return try await buffer.next()
  }
}

@available(*, unavailable)
extension AsyncBufferedByteIterator: Sendable { }

@frozen @usableFromInline
internal struct _AsyncBytesBuffer {
  @usableFromInline
  final class Storage {
    fileprivate let buffer: UnsafeMutableRawBufferPointer

    init(
      capacity: Int
    ) {
      precondition(capacity > 0)
      buffer = UnsafeMutableRawBufferPointer.allocate(
        byteCount: capacity,
        alignment: MemoryLayout<AnyObject>.alignment
      )
    }

    deinit {
      buffer.deallocate()
    }
  }

  @usableFromInline internal let storage: Storage
  @usableFromInline internal var nextPointer: UnsafeRawPointer
  @usableFromInline internal var endPointer: UnsafeRawPointer

  internal let readFunction: @Sendable (UnsafeMutableRawBufferPointer) async throws -> Int
  internal var finished = false

  @usableFromInline init(
    capacity: Int,
    readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int
  ) {
    let s = Storage(capacity: capacity)
    self.readFunction = readFunction
    storage = s
    nextPointer = UnsafeRawPointer(s.buffer.baseAddress!)
    endPointer = nextPointer
  }

  @inline(never) @usableFromInline
  internal mutating func reloadBufferAndNext() async throws -> UInt8? {
    if finished {
      return nil
    }
    try Task.checkCancellation()
    do {
      let readSize: Int = try await readFunction(storage.buffer)
      if readSize == 0 {
        finished = true
        nextPointer = endPointer
        return nil
      }
      nextPointer = UnsafeRawPointer(storage.buffer.baseAddress!)
      endPointer = nextPointer + readSize
    } catch {
      finished = true
      nextPointer = endPointer
      throw error
    }
    return try await next()
  }

  @inlinable @inline(__always)
  internal mutating func next() async throws -> UInt8? {
    if _fastPath(nextPointer != endPointer) {
      let byte = nextPointer.load(fromByteOffset: 0, as: UInt8.self)
      nextPointer = nextPointer + 1
      return byte
    }
    return try await reloadBufferAndNext()
  }
}

@rethrows
internal protocol _ErrorMechanism {
  associatedtype Output
  func get() throws -> Output
}

extension _ErrorMechanism {
  // rethrow an error only in the cases where it is known to be reachable
  internal func _rethrowError() rethrows -> Never {
    _ = try _rethrowGet()
    fatalError("materialized error without being in a throwing context")
  }

  internal func _rethrowGet() rethrows -> Output {
    return try get()
  }
}

extension Result: _ErrorMechanism { }



// stopgap cross-platform async FileHandle support from PR:
// https://github.com/apple/swift-corelibs-foundation/blob/f15da19f874a961a676b5257980e877d94c4630a/Sources/Foundation/FileHandle%2BAsync.swift


//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
final actor IOActor {
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func read(from fd: Int32, into buffer: UnsafeMutableRawBufferPointer) async throws -> Int {
        while true {
#if canImport(Darwin)
            let read = Darwin.read
#elseif canImport(Glibc)
            let read = Glibc.read
#elseif canImport(CRT)
            let read = CRT._read
#endif
            let amount = read(fd, buffer.baseAddress, buffer.count)
            if amount >= 0 {
                return amount
            }
            let posixErrno = errno
            if errno != EINTR {
                // TODO: get the path of the fd to provide a more informative error
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(posixErrno), userInfo: [:])
            }
        }
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func read(from handle: FileHandle, into buffer: UnsafeMutableRawBufferPointer) async throws -> Int {
        // this is not incredibly effecient but it is the best we have
        guard let data = try handle.read(upToCount: buffer.count) else {
            return 0
        }
        data.copyBytes(to: buffer)
        return data.count
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func createFileHandle(reading url: URL) async throws -> FileHandle {
        return try FileHandle(forReadingFrom: url)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    static let `default` = IOActor()
}



extension FileHandle {

    //public typealias AsyncBytes = FileAsyncBytes

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public struct FileAsyncBytes: AsyncSequence {
        public typealias Element = UInt8
        public typealias AsyncIterator = Iterator
        var handle: FileHandle

        internal init(file: FileHandle) {
            handle = file
        }

        public func makeAsyncIterator() -> Iterator {
            return Iterator(file: handle)
        }

        @frozen
        public struct Iterator: AsyncIteratorProtocol {

            @inline(__always) static var bufferSize: Int {
                16384
            }

            public typealias Element = UInt8
            @usableFromInline var buffer: _AsyncBytesBuffer

            internal var byteBuffer: _AsyncBytesBuffer {
                return buffer
            }

            internal init(file: FileHandle) {
                buffer = _AsyncBytesBuffer(capacity: Iterator.bufferSize)
                let fileDescriptor = file.fileDescriptor
                buffer.readFunction = { (buf) in
                    buf.nextPointer = buf.baseAddress
                    let capacity = buf.capacity
                    let bufPtr = UnsafeMutableRawBufferPointer(start: buf.nextPointer, count: capacity)
                    let readSize: Int
                    if fileDescriptor >= 0 {
                        readSize = try await IOActor.default.read(from: fileDescriptor, into: bufPtr)
                    } else {
                        readSize = try await IOActor.default.read(from: file, into: bufPtr)
                    }
                    buf.endPointer = buf.nextPointer + readSize
                    return readSize
                }
            }

            @inlinable @inline(__always)
            public mutating func next() async throws -> UInt8? {
                return try await buffer.next()
            }
        }
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public var bytesAsync: FileAsyncBytes {
        return FileAsyncBytes(file: self)
    }


    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @frozen @usableFromInline
    internal struct _AsyncBytesBuffer {

        struct Header {
            internal var readFunction: ((inout _AsyncBytesBuffer) async throws -> Int)? = nil
            internal var finished = false
        }

        class Storage : ManagedBuffer<Header, UInt8> {
            var finished: Bool {
                get { return header.finished }
                set { header.finished = newValue }
            }
        }

        var readFunction: (inout _AsyncBytesBuffer) async throws -> Int {
            get { return (storage as! Storage).header.readFunction! }
            set { (storage as! Storage).header.readFunction = newValue }
        }

        // The managed buffer is guaranteed to keep the bytes alive as long as it is alive.
        // This must be escaped to avoid the extra indirection step that
        // withUnsafeMutablePointerToElement incurs in the hot path
        // DO NOT COPY THIS APPROACH WITHOUT CONSULTING THE COMPILER TEAM
        // The reasons it's delicately safe here are:
        // • We never use the pointer to access a property (would violate exclusivity)
        // • We never access the interior of a value type (doesn't have a stable address)
        //     - This is especially delicate in the case of Data, where we have to force it out of its inline representation
        //       which can't be reliably done using public API
        // • We keep the reference we're accessing the interior of alive manually
        var baseAddress: UnsafeMutableRawPointer {
            (storage as! Storage).withUnsafeMutablePointerToElements { UnsafeMutableRawPointer($0) }
        }

        var capacity: Int {
            (storage as! Storage).capacity
        }

        var storage: AnyObject? = nil
        @usableFromInline internal var nextPointer: UnsafeMutableRawPointer
        @usableFromInline internal var endPointer: UnsafeMutableRawPointer

        @usableFromInline init(capacity: Int) {
            let s = Storage.create(minimumCapacity: capacity) { _ in
                return Header(readFunction: nil, finished: false)
            }
            storage = s
            nextPointer = s.withUnsafeMutablePointerToElements { UnsafeMutableRawPointer($0) }
            endPointer = nextPointer
        }

        @inline(never) @usableFromInline
        internal mutating func reloadBufferAndNext() async throws -> UInt8? {
            let storage = self.storage as! Storage
            if storage.finished {
                return nil
            }
            try Task.checkCancellation()
            nextPointer = storage.withUnsafeMutablePointerToElements { UnsafeMutableRawPointer($0) }
            do {
                let readSize = try await readFunction(&self)
                if readSize == 0 {
                    storage.finished = true
                }
            } catch {
                storage.finished = true
                throw error
            }
            return try await next()
        }

        @inlinable @inline(__always)
        internal mutating func next() async throws -> UInt8? {
            if _fastPath(nextPointer != endPointer) {
                let byte = nextPointer.load(fromByteOffset: 0, as: UInt8.self)
                nextPointer = nextPointer + 1
                return byte
            }
            return try await reloadBufferAndNext()
        }
    }
}
