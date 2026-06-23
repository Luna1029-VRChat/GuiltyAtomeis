# src/compiler/entropy_engine.nim
import os
import ../common/isa
{.passC: "-mrdrnd".}

const headerPath = "compiler/entropy_engine.hpp"
type AutonomousMalbolge* {.importcpp: "AutonomousMalbolge", header: headerPath.} = object

proc constructAuto*(): AutonomousMalbolge {.importcpp: "AutonomousMalbolge()", header: headerPath.}
proc initAutonomous*(this: var AutonomousMalbolge) {.importcpp: "#.init_autonomous()", header: headerPath.}
proc getRegister*(this: AutonomousMalbolge): int64 {.importcpp: "#.get_register()", header: headerPath.}
proc setRegister*(this: var AutonomousMalbolge, val: int64) {.importcpp: "#.set_register(@)", header: headerPath.}
proc force_self_checksum*(this: var AutonomousMalbolge, cs: uint32) {.importcpp: "#.force_self_checksum(@)", header: headerPath.}
proc getSelfChecksum*(this: var AutonomousMalbolge): uint64 {.importcpp: "#.get_self_checksum()", header: headerPath.}
proc armorId*(this: var AutonomousMalbolge): uint64 {.importcpp: "#.armor_id()", header: headerPath.}
proc opaqueVerify*(this: var AutonomousMalbolge): bool {.importcpp: "#.opaque_verify()", header: headerPath.}
proc decoy_loop*(this: var AutonomousMalbolge) {.importcpp: "#.decoy_loop()", header: headerPath.}
proc evolveIsa*(this: var AutonomousMalbolge, op: uint8) {.importcpp: "#.evolve_isa(@)", header: headerPath.}
proc getDynamicOffset*(this: AutonomousMalbolge, pc: uint64): uint32 {.importcpp: "#.get_dynamic_offset(@)", header: headerPath.}
proc generateTrueSpice*(this: var AutonomousMalbolge): uint64 {.importcpp: "#.generate_true_spice()", header: headerPath.}
proc getHistoryHash*(this: var AutonomousMalbolge, pc: uint64): uint32 {.importcpp: "#.get_history_hash(@)", header: headerPath.}
proc corruptHistory*(this: var AutonomousMalbolge) {.importcpp: "#.corrupt_history()", header: headerPath.}
proc getAccumulatedSin*(this: var AutonomousMalbolge): uint64 {.importcpp: "#.get_accumulated_sin()", header: headerPath.}
proc setAccumulatedSin*(this: var AutonomousMalbolge, s: uint64) {.importcpp: "#.set_accumulated_sin(@)", header: headerPath.}
proc conductAbsolution*(this: var AutonomousMalbolge, sin, integrity, next_sin: uint64): bool {.importcpp: "#.conduct_absolution(@)", header: headerPath.}
proc privilegedLock*(this: var AutonomousMalbolge) {.importcpp: "#.privileged_lock()", header: headerPath.}

proc encrypt_fhe_cpp(this: var AutonomousMalbolge, data: int32, spice, pc: uint64, low, high: ptr uint64) {.importcpp: "#.encrypt_fhe(@)", header: headerPath.}

proc encryptFhe*(this: var AutonomousMalbolge, data: int32, spice, pc: uint64): FheBlock =
  var low, high: uint64
  this.encrypt_fhe_cpp(data, spice, pc, addr low, addr high)
  result = FheBlock(low: low, high: high)

proc decrypt_fhe_cpp(this: var AutonomousMalbolge, low, high, pc: uint64): int32 {.importcpp: "#.decrypt_fhe(@)", header: headerPath.}

proc decryptFhe*(this: var AutonomousMalbolge, fheBlk: FheBlock, pc: uint64): int32 =
  this.decrypt_fhe_cpp(fheBlk.low, fheBlk.high, pc)

proc decryptFheLow*(this: var AutonomousMalbolge, low: uint64, pc: uint64): int32 =
  this.decryptFhe(FheBlock(low: low, high: 0), pc)

proc stableEncryptCpp(this: var AutonomousMalbolge, data: int32, index: uint64, out_low, out_high: ptr uint64) {.importcpp: "#.stable_encrypt(@)", header: headerPath.}
proc stableDecryptCpp(this: var AutonomousMalbolge, in_low, in_high, index: uint64): int32 {.importcpp: "#.stable_decrypt(@)", header: headerPath.}
proc fheAddCpp(this: var AutonomousMalbolge, a_low, a_high, a_idx, b_low, b_high, b_idx, out_idx: uint64, out_low, out_high: ptr uint64) {.importcpp: "#.fhe_add(@)", header: headerPath.}
proc fheSubCpp(this: var AutonomousMalbolge, a_low, a_high, a_idx, b_low, b_high, b_idx, out_idx: uint64, out_low, out_high: ptr uint64) {.importcpp: "#.fhe_sub(@)", header: headerPath.}

proc stableEncrypt*(this: var AutonomousMalbolge, data: int32, index: int): FheBlock =
    var low, high: uint64
    this.stableEncryptCpp(data, index.uint64, addr low, addr high)
    result = FheBlock(low: low, high: high)

proc stableDecrypt*(this: var AutonomousMalbolge, blk: FheBlock, index: int): int32 =
    result = this.stableDecryptCpp(blk.low, blk.high, index.uint64)

proc fheAdd*(this: var AutonomousMalbolge, a, b: FheBlock, a_idx, b_idx, out_idx: int): FheBlock =
    var low, high: uint64
    this.fheAddCpp(a.low, a.high, a_idx.uint64, b.low, b.high, b_idx.uint64, out_idx.uint64, addr low, addr high)
    result = FheBlock(low: low, high: high)

proc fheSub*(this: var AutonomousMalbolge, a, b: FheBlock, a_idx, b_idx, out_idx: int): FheBlock =
    var low, high: uint64
    this.fheSubCpp(a.low, a.high, a_idx.uint64, b.low, b.high, b_idx.uint64, out_idx.uint64, addr low, addr high)
    result = FheBlock(low: low, high: high)

proc rotateLeft*(this: var AutonomousMalbolge, val, steps: uint8): uint8 =
    let s = steps mod 8
    result = (val shl s) or (val shr (8 - s))

proc rotateRight*(this: var AutonomousMalbolge, val, steps: uint8): uint8 =
    let s = steps mod 8
    result = (val shr s) or (val shl (8 - s))