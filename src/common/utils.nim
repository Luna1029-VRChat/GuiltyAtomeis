# src/common/utils.nim
# GuiltyAtomeis V10 — Shared Utilities

import osproc, uri, strutils, times, constants

# 1. 高度な文字列難読化 (Compiler/Runtime 用)
proc obfuscateString*(s: string, seed: int64): string =
  result = s
  var k = uint64(seed)
  for i in 0 ..< result.len:
    let orig = uint8(result[i])
    result[i] = chr(orig xor uint8(k and 0xFF))
    k = (k * 0x9e3779b9'u64) xor uint64(orig) xor (k shr 13)

proc deobfuscateString*(s: string, seed: int64): string =
  result = s
  var k = uint64(seed)
  for i in 0 ..< result.len:
    let decrypted = uint8(result[i]) xor uint8(k and 0xFF)
    result[i] = chr(decrypted)
    k = (k * 0x9e3779b9'u64) xor uint64(decrypted) xor (k shr 13)


