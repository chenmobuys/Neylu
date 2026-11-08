import Foundation
import Testing
import zlib

func bigEndian(_ value: UInt32) -> Data {
  var word = value.bigEndian
  return Data(bytes: &word, count: 4)
}
func pngChunk(_ name: String, _ bytes: Data) -> Data {
  let content = Data(name.utf8) + bytes
  let crc = content.withUnsafeBytes {
    crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(content.count))
  }
  return bigEndian(UInt32(bytes.count)) + content + bigEndian(UInt32(crc))
}
func binaryChunks(_ data: Data, start: Int, png: Bool = false) throws -> [(String, Data)] {
  var position = start
  var output: [(String, Data)] = []
  func number(_ offset: Int) -> Int {
    Int(data[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
  }
  while position < data.count {
    try #require(position + 8 <= data.count)
    let length = number(position + (png ? 0 : 4))
    let size = png ? length + 12 : length
    try #require(size >= (png ? 12 : 8) && position + size <= data.count)
    let nameStart = position + (png ? 4 : 0)
    let name = String(data: data[nameStart..<nameStart + 4], encoding: .ascii)!
    output.append((name, Data(data[position + 8..<position + size - (png ? 4 : 0)])))
    position += size
  }
  return output
}
extension NeyluTests {
  @Test func losslessIconOptimization() throws {
    let pixels =
      Data([0])
      + Data(Array(repeating: [UInt8(0x10), 0x20, 0x30, 0xff], count: 1024).flatMap { $0 })
    var compressed = Data(count: Int(compressBound(uLong(pixels.count))))
    var length = uLongf(compressed.count)
    let code = compressed.withUnsafeMutableBytes { out in
      pixels.withUnsafeBytes { input in
        compress2(
          out.bindMemory(to: Bytef.self).baseAddress!, &length,
          input.bindMemory(to: Bytef.self).baseAddress!, uLong(pixels.count), 1)
      }
    }
    try #require(code == Z_OK)
    compressed.count = Int(length)
    let png =
      Data([137, 80, 78, 71, 13, 10, 26, 10])
      + pngChunk("IHDR", bigEndian(1024) + bigEndian(1) + Data([8, 6, 0, 0, 0]))
      + pngChunk("tEXt", Data("Comment\0preserve metadata".utf8)) + pngChunk("IDAT", compressed)
      + pngChunk("IEND", Data())
    let originalParts = [("ic09", png), ("ic10", png), ("info", Data("metadata".utf8))]
    var body = Data()
    for (kind, value) in originalParts {
      body += Data(kind.utf8) + bigEndian(UInt32(value.count + 8)) + value
    }
    let original = Data("icns".utf8) + bigEndian(UInt32(body.count + 8)) + body
    let f = try ToolFixture()
    let path = try f.write("Icon.icns", original)
    try ToolRunner.requireSuccess(ToolRunner.python("Assets/optimize-icon.py", [path.path]))
    let optimized = try Data(contentsOf: path)
    #expect(optimized.count < original.count)
    try ToolRunner.requireSuccess(ToolRunner.python("Assets/optimize-icon.py", [path.path]))
    #expect(try Data(contentsOf: path) == optimized)
    let parts = try binaryChunks(optimized, start: 8)
    #expect(parts.map { $0.0 } == originalParts.map { $0.0 })
    for ((_, old), (_, new)) in zip(originalParts, parts) {
      if old.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
        let before = try binaryChunks(old, start: 8, png: true)
        let after = try binaryChunks(new, start: 8, png: true)
        #expect(
          before.filter { $0.0 != "IDAT" }.map { $0.0 }
            == after.filter { $0.0 != "IDAT" }.map { $0.0 })
        #expect(
          before.filter { $0.0 != "IDAT" }.map { $0.1 }
            == after.filter { $0.0 != "IDAT" }.map { $0.1 })
        let encoded = after.filter { $0.0 == "IDAT" }.reduce(Data()) { $0 + $1.1 }
        var decoded = Data(count: pixels.count)
        var size = uLongf(pixels.count)
        let status = decoded.withUnsafeMutableBytes { out in
          encoded.withUnsafeBytes { input in
            uncompress(
              out.bindMemory(to: Bytef.self).baseAddress!, &size,
              input.bindMemory(to: Bytef.self).baseAddress!, uLong(encoded.count))
          }
        }
        #expect(status == Z_OK && decoded == pixels)
      } else {
        #expect(new == old)
      }
    }
  }
  @Test func malformedIconContainers() throws {
    let f = try ToolFixture()
    for (index, data) in [
      Data(), Data("icns".utf8) + bigEndian(9),
      Data("icns".utf8) + bigEndian(16) + Data("ic10".utf8) + bigEndian(0),
    ].enumerated() {
      let path = try f.write("bad-\(index).icns", data)
      ToolRunner.requireRejected(try ToolRunner.python("Assets/optimize-icon.py", [path.path]))
    }
  }
}
