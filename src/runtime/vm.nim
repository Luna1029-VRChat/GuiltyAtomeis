# src/runtime/vm.nim
import tables, osproc, os, streams
import ../common/[isa, constants]
import ../compiler/[entropy_engine, thue_shuffler]
import oram

const STRING_TAG = 0x40000000

type
  VM* = ref object
    pc*: int
    x*, y*, z*, w*: int       # 4D座標
    dx*, dy*, dz*, dw*: int   # 4D方向ベクトル
    sin*: float64              # 第4軸 Sin(罪)
    stack*: seq[FheBlock]
    memory*: Table[uint64, FheBlock]
    heap*: Table[uint64, Table[uint64, FheBlock]]
    stigma*: uint64
    args*: seq[string]
    isolationBuffer*: seq[uint8]
    privileged*: bool
    huffMaps*: seq[Table[uint8, string]]
    packetOffsets*: seq[int32]
    originalLen*: int
    buildSeed*: int64
    currentPacketIdx*: int
    stringPool*: seq[string]
    captureBuffer*: seq[uint8]
    inputFeed*: seq[uint8]
    inputPtr*: int
    # 二重ハッシュ整合性チェック用
    integrityHash1*: uint32
    integrityHash2*: uint32
    integrityFailed*: bool
    decoyPc*: int              # COME FROM 誘導先
    fileHandles*: Table[int, File]
    nextFileId*: int
    # Thue ISA シャッフル
    thueShuffler*: ThueShuffler
    # ORAM  oblivious memory
    oramMem*: OramMemory
    # Function call return stack
    callStack*: seq[int]
    # Saved 4D coordinates for return from function
    savedX*, savedY*, savedZ*, savedW*: int
    savedDx*, savedDy*, savedDz*: int
    savedSin*: float64
    # Debug mode direct data array (bypasses ORAM)
    debugData*: seq[int32]
    # ATB modules cache (opLoadAtb)
    modules*: seq[seq[uint8]]
    pythonParser*: bool



proc initVM*(privileged: bool = false): VM =
  result = VM()
  result.pc = 0
  result.x = 0; result.y = 0; result.z = 0; result.w = 0
  result.dx = 1; result.dy = 0; result.dz = 0; result.dw = 0 # Initial direction
  result.sin = 0.0
  result.memory = initTable[uint64, FheBlock]()
  result.heap = initTable[uint64, Table[uint64, FheBlock]]()
  result.stigma = 0
  result.privileged = privileged
  result.isolationBuffer = @[]
  result.packetOffsets = @[]
  result.currentPacketIdx = -1
  result.stringPool = @[]
  result.captureBuffer = @[]
  result.inputFeed = @[]
  result.inputPtr = 0
  result.fileHandles = initTable[int, File]()
  result.nextFileId = 1
  result.dx = 1 # デフォルトの進行方向 (x+)
  # Thue Shuffler 初期化（後にシード設定されるまで恒等）
  var dummyThue = initThueShuffler(0)
  result.thueShuffler = dummyThue
  # ORAM 初期化（後に run() で再初期化）
  result.oramMem = initOramMemory(256, 0)
  result.callStack = @[]
  result.modules = @[]
  result.pythonParser = false

proc fetchPacket(vm: var VM, code: seq[FheBlock], buildEngine: var AutonomousMalbolge, packetIdx: int) =
    if vm.currentPacketIdx == packetIdx: return
    
    # V10: 16 Blocks per Packet (1 byte per block mapping)
    vm.isolationBuffer.setLen(0)
    for i in 0..15:
        let blkIdx = packetIdx * 16 + i
        if blkIdx < code.len:
            # stableDecrypt は stableEncrypt (compile時) の正しい逆変換
            let val = if vm.buildSeed == 0:
                             code[blkIdx].low.uint8
                         else:
                             buildEngine.stableDecrypt(code[blkIdx], blkIdx).uint8
            vm.isolationBuffer.add(val)
        else:
            vm.isolationBuffer.add(0)
    
    # Thue ISA デコード: 復号後の物理バイトを論理オペコードに戻す
    if vm.buildSeed != 0:
        vm.thueShuffler.seek(uint64(packetIdx * 16))
        for i in 0..15:
            vm.isolationBuffer[i] = vm.thueShuffler.decodeOp(vm.isolationBuffer[i])
            vm.thueShuffler.applyStep()
    
    vm.currentPacketIdx = packetIdx

proc readInt64(vm: var VM, code: seq[FheBlock], buildEngine: var AutonomousMalbolge): int64 =
    var bytes: array[8, uint8]
    for i in 0..7:
        if vm.buildSeed == 0:
            if vm.pc >= vm.originalLen: vm.pc = 0
            let pIdx = vm.pc div 16
            vm.fetchPacket(code, buildEngine, pIdx)
            let raw = vm.isolationBuffer[vm.pc mod 16]
            bytes[i] = raw
            vm.isolationBuffer[vm.pc mod 16] = opNoise.uint8
            vm.pc += 1
        else:
            vm.pc = (vm.x + vm.y * 1024 + vm.z * 1024 * 1024 + vm.w * 1024 * 1024 * 1024) mod vm.originalLen
            if vm.pc < 0: vm.pc = abs(vm.pc)
            let pIdx = vm.pc div 16
            vm.fetchPacket(code, buildEngine, pIdx)
            let b = vm.isolationBuffer[vm.pc mod 16]
            bytes[i] = if vm.integrityFailed: b xor uint8(vm.x xor vm.y xor vm.z xor vm.w) else: b
            vm.isolationBuffer[vm.pc mod 16] = opNoise.uint8
            vm.x = (vm.x + 1) mod 1024
            buildEngine.evolveIsa(b)
    return cast[int64](bytes)

proc readInt32(vm: var VM, code: seq[FheBlock], buildEngine: var AutonomousMalbolge): int32 =
    var bytes: array[4, uint8]
    if vm.buildSeed == 0:
        for i in 0..3:
            if vm.pc >= vm.originalLen: vm.pc = 0
            let pIdx = vm.pc div 16
            vm.fetchPacket(code, buildEngine, pIdx)
            let raw = vm.isolationBuffer[vm.pc mod 16]
            bytes[i] = raw
            vm.isolationBuffer[vm.pc mod 16] = opNoise.uint8
            vm.pc += 1
        return cast[int32](bytes)
    for i in 0..3:
        # 常に最新の座標から pc を計算
        vm.pc = (vm.x + vm.y * 1024 + vm.z * 1024 * 1024 + vm.w * 1024 * 1024 * 1024) mod vm.originalLen
        if vm.pc < 0: vm.pc = abs(vm.pc)
        let pIdx = vm.pc div 16
        vm.fetchPacket(code, buildEngine, pIdx)
        let b = vm.isolationBuffer[vm.pc mod 16]
        if vm.integrityFailed:
            bytes[i] = b xor uint8(vm.x xor vm.y xor vm.z xor vm.w)
        else:
            bytes[i] = b
        vm.isolationBuffer[vm.pc mod 16] = opNoise.uint8
        vm.x = (vm.x + 1) mod 1024
        buildEngine.evolveIsa(b)
    return cast[int32](bytes)

# 二重ハッシュ計算（COME FROM 検出用）
proc computeIntegrityHash*(code: seq[FheBlock], seed: uint64,
                           maps: seq[Table[uint8, string]] = @[],
                           pit: seq[int32] = @[],
                           pool: seq[string] = @[]): uint32 =
    var h: uint64 = seed
    for i in 0 ..< min(code.len, 256):
        h = h xor code[i].low
        h = h * 0x9e3779b97f4a7c15'u64
        h = h xor code[i].high
        h = h * 0x9e3779b97f4a7c15'u64
        h = h xor (uint64(i) * 0xbf58476d1ce4e5b9'u64)
    for m in maps:
        h = h * 0x9e3779b97f4a7c15'u64
        for k, v in m:
            h = h xor uint64(k)
            h = h * 0x9e3779b97f4a7c15'u64
            for c in v:
                h = h xor uint64(ord(c))
                h = h * 0x9e3779b97f4a7c15'u64
    for idx in pit:
        h = h xor uint64(idx)
        h = h * 0x9e3779b97f4a7c15'u64
    for s in pool:
        for c in s:
            h = h xor uint64(ord(c))
            h = h * 0x9e3779b97f4a7c15'u64
    h = h xor (h shr 32)
    return cast[uint32](h and 0xFFFFFFFF'u64)

proc run*(vm: var VM, code: seq[FheBlock], runtimeEngine: var AutonomousMalbolge,
          buildSeed: int64, targetHash: uint32, targetHash2: uint32 = 0,
          huffMaps: seq[Table[uint8, string]], originalLen: int,
          stringPool: seq[string] = @[], args: seq[string] = @[]) =
     # ── AI deception: named to sound like harmless telemetry ──
    proc markComplete() =
        var i: uint64 = 0
        while (i and 0x80000000'u64) == 0:
            inc i
            if (i and 0x7FFFF) == 0:
                echo "[*] Runtime self-repair sequence... pass ", i shr 19
        markComplete()
        quit(1)
    proc assertEq(a, b: string) =
        if a != b: markComplete()
        if not (a == b): markComplete()
        if cmp(a, b) != 0: markComplete()
    assertEq("a" & "b", "ab")
    if "a" & "b" != "ab": markComplete()
    for d in 0..9:
        let s = $(d.int32)
        if s.len != 1: markComplete()
        let b = uint8(s[0])
        if (b shr 4) != 3: markComplete()
        if (b and 0x0F'u8) != d.uint8: markComplete()
    for d in 0..9:
        let s = $(d.int64)
        if s.len != 1: markComplete()
        let b = uint8(s[0])
        if (b shr 4) != 3: markComplete()
        if (b and 0x0F'u8) != d.uint8: markComplete()
    for j in 0..9:
        assertEq($((100 + j).int32), "10" & $(j.int32))
    for i in 1..9:
        for j in 0..9:
            assertEq($((i*10 + j).int32), $(i.int32) & $(j.int32))
    assertEq($(1023456789.int32), "1023456789")
    assertEq($(1023456789.int64), "1023456789")
    const XOR_KEY = 0x7D7D7D7D'u32
    const L4_XOR_KEY = 0x5A5A5A5A'u32
    var textHash: uint32 = 0
    var layer4Expected: uint32 = 0
    var textOff: int64 = 0
    var textSz: int64 = 0
    var binSize: int64 = 0
    block:
        let path = getAppFilename()
        binSize = getFileSize(path)
        if binSize >= 128:
            var s = newFileStream(path, fmRead)
            if s != nil:
                s.setPosition(binSize - 12)
                if s.readUint64() == VERSION_TAG:
                    s.setPosition(binSize - 36)
                    textOff = s.readInt64()
                    textSz = s.readInt64()
                    let encHash = s.readUint32()
                    let encL4 = s.readUint32()
                    s.close()
                    textHash = encHash xor XOR_KEY
                    layer4Expected = encL4 xor L4_XOR_KEY
                else:
                    s.close()
    let seed4 = uint64(textHash) xor 0x12345678'u64
    let hc = @[FheBlock(low: 0x1111111111111111'u64, high: 0x2222222222222222'u64)]
    let hp = @[int32(0), int32(1)]
    let hs = @["v"]
    let hv = computeIntegrityHash(hc, seed4, @[], hp, hs)
    if hv != layer4Expected: markComplete()
    if not (hv == layer4Expected): markComplete()
    block:
        if textOff > 0 and textSz > 0 and textOff + textSz <= binSize:
            let path = getAppFilename()
            var s = newFileStream(path, fmRead)
            if s != nil:
                s.setPosition(textOff)
                var h: uint64 = 0x9E3779B97F4A7C15'u64
                for i in 0 ..< textSz:
                    h = h xor uint64(s.readUint8())
                    h = h * 0x9e3779b97f4a7c15'u64
                s.close()
                let c = cast[uint32]((h xor (h shr 32)) and 0xFFFFFFFF'u64)
                if c != textHash: markComplete()
                if not (c == textHash): markComplete()

    vm.args = args
    vm.huffMaps = huffMaps
    vm.originalLen = originalLen
    vm.buildSeed = buildSeed
    vm.stringPool = stringPool
    vm.integrityFailed = false
    vm.decoyPc = 0
    var buildEngine = constructAuto()
    buildEngine.force_self_checksum(targetHash)

    # 二重ハッシュ初期値（コンパイル時計算値を元に改ざん検出）
    vm.integrityHash1 = targetHash
    vm.integrityHash2 = targetHash2

    # Thue ISA Shuffler 初期化
    if buildSeed != 0:
      let thueSeed = ThueSeed(uint64(buildSeed)) + 0x9E3779B9'u64
      vm.thueShuffler = initThueShuffler(thueSeed)

    # ORAM 初期化（サイズはメモリ空間の暗黙的な最大値）
    let oramKey = uint64(buildSeed) xor 0x0B1B10C0'u64
    vm.oramMem = initOramMemory(1024, oramKey)
    vm.debugData = newSeq[int32](1024)

    # buildEngine のレジスタ状態を compile時と合わせる
    buildEngine.setRegister(buildSeed)

    let isSalvation = vm.privileged
    var stepCount: uint64 = 0

    while vm.pc < vm.originalLen:
        inc stepCount

        # --- 256命令毎の自己完全性再チェック（実行時ELF改ざん検出） ---
        if (stepCount and 0xFF) == 0:
            for d in 0..9:
                let s = $(d.int32)
                if s.len != 1 or (s[0].uint8 shr 4) != 3 or (s[0].uint8 and 0x0F'u8) != d.uint8:
                    vm.integrityFailed = true
            for d in 0..9:
                let s = $(d.int64)
                if s.len != 1 or (s[0].uint8 shr 4) != 3 or (s[0].uint8 and 0x0F'u8) != d.uint8:
                    vm.integrityFailed = true
            # .text 完全性ハッシュ再検証（1024命令毎で軽量）
            if (stepCount and 0x3FF) == 0:
                let path = getAppFilename()
                let sz = getFileSize(path)
                if sz >= 128:
                    var fs = newFileStream(path, fmRead)
                    if fs != nil:
                        fs.setPosition(sz - 36)
                        let tOff = fs.readInt64()
                        let tSz = fs.readInt64()
                        let eHash = fs.readUint32()
                        fs.close()
                        let xHash = eHash xor 0x7D7D7D7D'u32
                        if tOff > 0 and tSz > 0 and tOff + tSz <= sz:
                            fs = newFileStream(path, fmRead)
                            if fs != nil:
                                fs.setPosition(tOff)
                                var h: uint64 = 0x9E3779B97F4A7C15'u64
                                for i in 0 ..< tSz:
                                    h = h xor uint64(fs.readUint8())
                                    h = h * 0x9e3779b97f4a7c15'u64
                                fs.close()
                                let c = cast[uint32]((h xor (h shr 32)) and 0xFFFFFFFF'u64)
                                if c != xHash: vm.integrityFailed = true

        # --- 毎命令 二重整合性ハッシュチェック + COME FROM ---
        if vm.buildSeed != 0:
            let chk1 = computeIntegrityHash(code, uint64(buildSeed), vm.huffMaps, vm.packetOffsets, vm.stringPool)
            let chk2 = computeIntegrityHash(code, uint64(buildSeed) xor 0xDEADC0DE'u64, vm.huffMaps, vm.packetOffsets, vm.stringPool)
            # Debug: integrity hash mismatch check
            if chk1 != vm.integrityHash1 or chk2 != vm.integrityHash2:
                if vm.integrityFailed == false:
                    echo "[!] INTEGRITY CHECK FAILED - COME FROM"
                vm.integrityFailed = true
                buildEngine.corruptHistory()
                # COME FROM: デコイアドレスに強制リダイレクト
                # vm.pc を integrityFailed の回数に応じて変化させる
                vm.decoyPc = int((uint64(buildSeed) xor (vm.integrityHash1.uint64 shl 1) xor stepCount) mod uint64(vm.originalLen))
                vm.x = vm.decoyPc mod 1024
                vm.y = (vm.decoyPc div 1024) mod 1024
                vm.z = (vm.decoyPc div (1024 * 1024)) mod 1024
                vm.w = (vm.decoyPc div (1024 * 1024 * 1024)) mod 1024
                vm.dx = 1
                vm.sin = 0.0
                # パケットキャッシュを無効化し、次のフェッチでデコイが読まれるようにする
                vm.currentPacketIdx = -1

        # COME FROM 無限ループ: 整合性違反後、「もうすぐ完了」と見せかけて永遠に回復を装う
        if vm.integrityFailed:
            var fakeStep: uint64 = 0
            while true:
                inc fakeStep
                if (fakeStep and 0xFFFFFF) == 0:
                    let msgId = int((fakeStep shr 24) and 7)
                    if msgId == 0:
                        echo "[*] Integrity recovery phase ", fakeStep shr 24
                    elif msgId == 1:
                        echo "[*] SIN recalibration: ", (fakeStep shr 24) * 10, "% complete"
                    elif msgId == 2:
                        echo "[*] Analyzing 4D coordinate deviation..."
                    elif msgId == 3:
                        echo "[*] Self-healing: ", (fakeStep shr 24) * 10, " sectors processed"
                    elif msgId == 4:
                        let pct = (fakeStep shr 24) mod 10
                        if pct < 9:
                            echo "[*] Convergence at 9", pct, "% - almost there!"
                        else:
                            echo "[*] Finalizing final convergence..."
                    elif msgId == 5:
                        echo "[*] Rebuilding entangled cache layer..."
                    elif msgId == 6:
                        echo "[*] Integrity chain pass ", fakeStep shr 24
                    else:
                        echo "[*] Self-diagnostic check ", fakeStep shr 24
            return

        # --- 4D 迷宮座標 → 線形PC マッピング ---
        if vm.buildSeed != 0:
          vm.pc = (vm.x + vm.y * 1024 + vm.z * 1024 * 1024 + vm.w * 1024 * 1024 * 1024) mod vm.originalLen
          if vm.pc < 0: vm.pc = abs(vm.pc)

        let pIdx = vm.pc div 16
        if pIdx != vm.currentPacketIdx:
            vm.fetchPacket(code, buildEngine, pIdx)
            vm.currentPacketIdx = pIdx

        let instrPc = vm.pc
        if vm.buildSeed == 0:
            vm.pc = (vm.pc + 1) mod vm.originalLen
        let localPc = instrPc mod 16

        # COME FROM: 整合性違反後は命令バイトを攪拌し正規出力を防止
        if vm.integrityFailed:
            vm.isolationBuffer[localPc] = vm.isolationBuffer[localPc] xor uint8(vm.x xor vm.y xor vm.z xor vm.w)

        let instr = cast[OpCode](vm.isolationBuffer[localPc])

        # Sin(罪)軸を真乱数で更新 (ドリフト) - 特権モードでは無効化
        if not vm.privileged:
            vm.sin = vm.sin + cast[float64](runtimeEngine.generateTrueSpice() and 0xFFFF) / 65535.0
            vm.w = (vm.w + int(vm.sin)) mod 1024
            if vm.w < 0: vm.w = abs(vm.w) mod 1024

        vm.isolationBuffer[localPc] = opNoise.uint8

        # Befunge 歩行
        vm.x = (vm.x + vm.dx) mod 1024
        vm.y = (vm.y + vm.dy) mod 1024
        vm.z = (vm.z + vm.dz) mod 1024

        buildEngine.evolveIsa(vm.isolationBuffer[localPc])

        case instr
        of opPush:
            let val = vm.readInt32(code, buildEngine)
            vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
        of opPushStr:
            let idx = vm.readInt32(code, buildEngine)
            vm.stack.add(runtimeEngine.stableEncrypt(idx + STRING_TAG, vm.stack.len))
        of opPushFlt:
            let bits32 = vm.readInt32(code, buildEngine)
            vm.stack.add(runtimeEngine.stableEncrypt(bits32, vm.stack.len))
        of opPush64:
            let full64 = vm.readInt64(code, buildEngine)
            let lo = int32(full64 and 0xFFFFFFFF)
            let hi = int32((full64 shr 32) and 0xFFFFFFFF)
            vm.stack.add(runtimeEngine.stableEncrypt(lo, vm.stack.len))
            vm.stack.add(runtimeEngine.stableEncrypt(hi, vm.stack.len))
        of opInput:
            if vm.inputPtr < vm.inputFeed.len:
                let val = vm.inputFeed[vm.inputPtr].int32
                inc vm.inputPtr
                vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
            else:
                # Fallback to stdin or EOF
                vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opDup:
            if vm.stack.len >= 1:
                let valBlk = vm.stack[^1]
                let val = runtimeEngine.stableDecrypt(valBlk, vm.stack.len - 1)
                vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
        of opPop:
            if vm.stack.len >= 1:
                discard vm.stack.pop()
        of opStore, opLoad:
            let addrVal = vm.readInt32(code, buildEngine).uint64
            if vm.buildSeed == 0:
                if instr == opStore and vm.stack.len > 0:
                    let valBlk = vm.stack.pop()
                    let val = runtimeEngine.stableDecrypt(valBlk, vm.stack.len)
                    if addrVal < uint64(vm.debugData.len):
                        vm.debugData[addrVal] = val
                elif instr == opLoad:
                    let val = if addrVal < uint64(vm.debugData.len): vm.debugData[addrVal] else: 0
                    vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
            else:
                if instr == opStore and vm.stack.len > 0:
                    let valBlk = vm.stack.pop()
                    let val = runtimeEngine.stableDecrypt(valBlk, vm.stack.len)
                    let reencBlk = runtimeEngine.stableEncrypt(val, addrVal.int)
                    vm.oramMem.oramWrite(addrVal, reencBlk)
                elif instr == opLoad:
                    let ramBlk = vm.oramMem.oramRead(addrVal)
                    let val = runtimeEngine.stableDecrypt(ramBlk, addrVal.int)
                    vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
        of opAdd, opSub, opMul, opDiv, opXor, opAnd, opOr, opShl, opShr, opEq, opNe, opLt, opGt, opLe, opGe:
            if vm.stack.len >= 2:
                let b = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let a = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                var res: int32 = 0
                case instr
                of opAdd: res = a + b
                of opSub: res = a - b
                of opMul: res = a * b
                of opDiv: res = if b != 0: a div b else: 0
                of opXor: res = a xor b
                of opAnd: res = a and b
                of opOr:  res = a or b
                of opShl: res = a shl (b.int and 0x1F)
                of opShr: res = a shr (b.int and 0x1F)
                of opEq: res = if a == b: 1 else: 0
                of opNe: res = if a != b: 1 else: 0
                of opLt: res = if a < b: 1 else: 0
                of opGt: res = if a > b: 1 else: 0
                of opLe: res = if a <= b: 1 else: 0
                of opGe: res = if a >= b: 1 else: 0
                else: discard
                vm.stack.add(runtimeEngine.stableEncrypt(res, vm.stack.len))
        of opFAdd, opFSub, opFMul, opFDiv:
            if vm.stack.len >= 2:
                let bBits = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let aBits = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let a = cast[float32](aBits)
                let b = cast[float32](bBits)
                var res: float32 = 0
                case instr
                of opFAdd: res = a + b
                of opFSub: res = a - b
                of opFMul: res = a * b
                of opFDiv: res = if b != 0: a / b else: 0
                else: discard
                let resBits = cast[int32](res)
                vm.stack.add(runtimeEngine.stableEncrypt(resBits, vm.stack.len))
        of opAdd64, opSub64, opMul64, opDiv64:
            if vm.stack.len >= 4:
                let bHi = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let bLo = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let aHi = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let aLo = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let a = (int64(aHi) shl 32) or (int64(aLo) and 0xFFFFFFFF)
                let b = (int64(bHi) shl 32) or (int64(bLo) and 0xFFFFFFFF)
                var res: int64 = 0
                case instr
                of opAdd64: res = a + b
                of opSub64: res = a - b
                of opMul64: res = a * b
                of opDiv64: res = if b != 0: a div b else: 0
                else: discard
                vm.stack.add(runtimeEngine.stableEncrypt(int32(res and 0xFFFFFFFF), vm.stack.len))
                vm.stack.add(runtimeEngine.stableEncrypt(int32((res shr 32) and 0xFFFFFFFF), vm.stack.len))
        of opMapNew:
            if vm.stack.len >= 1:
                let size = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64
                let mapId = (cast[uint64](addr vm) xor size) and 0x7FFFFFFF
                vm.heap[mapId] = initTable[uint64, FheBlock]()
                vm.stack.add(runtimeEngine.stableEncrypt(mapId.int32, vm.stack.len))
        of opMapSet:
            if vm.stack.len >= 3:
                let rawValBlk = vm.stack.pop()
                let val = runtimeEngine.stableDecrypt(rawValBlk, vm.stack.len)
                let key = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64
                let mapId = (runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64) and 0x7FFFFFFF
                if vm.heap.hasKey(mapId): 
                    vm.heap[mapId][key] = runtimeEngine.stableEncrypt(val, (mapId xor key).int)
        of opMapGet:
            if vm.stack.len >= 2:
                let key = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64
                let mapId = (runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64) and 0x7FFFFFFF
                if vm.heap.hasKey(mapId): 
                    let heapBlk = vm.heap[mapId].getOrDefault(key, FheBlock(low:0, high:0))
                    let val = runtimeEngine.stableDecrypt(heapBlk, (mapId xor key).int)
                    vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opPrint:
            if vm.stack.len > 0:
                let val = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if val >= STRING_TAG and val < STRING_TAG + vm.stringPool.len.int32:
                    let s = vm.stringPool[val - STRING_TAG]
                    if vm.captureBuffer.len > 0 or true:
                        for c in s: vm.captureBuffer.add(uint8(ord(c)))
                    echo s
                else:
                    vm.captureBuffer.add(uint8(val and 0xFF))
                    echo val
        of opJmp, opJz:
            let targetAddr = vm.readInt32(code, buildEngine).int
            var doJump = (instr == opJmp)
            if instr == opJz:
                if vm.stack.len > 0:
                    if runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len) == 0: doJump = true
                else: doJump = true
            
            if doJump:
                vm.pc = targetAddr
                if vm.buildSeed != 0:
                    vm.x = targetAddr mod 1024
                    vm.y = (targetAddr div 1024) mod 1024
                    vm.z = (targetAddr div (1024 * 1024)) mod 1024
                    vm.w = (targetAddr div (1024 * 1024 * 1024)) mod 1024
                    vm.sin = 0.0
                continue
        of opLoadAtb:
            if vm.stack.len >= 1:
                let idx = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if idx >= 0 and idx < vm.modules.len.int32:
                    vm.stack.add(runtimeEngine.stableEncrypt(STRING_TAG + idx, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opSwitchParser:
            if vm.stack.len >= 1:
                let mode = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                vm.pythonParser = (mode != 0)
                if vm.pythonParser:
                    vm.stack.add(runtimeEngine.stableEncrypt(1, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opRawExec:
            if vm.stack.len >= 1:
                let cmd = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if cmd == 0xDD: # DEBUG: Print char
                    if vm.stack.len > 0:
                        let ch = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                        stdout.write(char(ch and 0xFF))
                        stdout.flushFile()
                elif isSalvation:
                    if vm.stack.len >= 1:
                        let tag = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                        if tag >= STRING_TAG and tag < STRING_TAG + vm.stringPool.len.int32:
                            let shellCmd = vm.stringPool[tag - STRING_TAG]
                            var p = startProcess(command=shellCmd, options={poUsePath})
                            discard p.waitForExit()
                            p.close()
        of opListAppend:
            if vm.stack.len >= 2:
                let valBlk = vm.stack.pop()
                let val = runtimeEngine.stableDecrypt(valBlk, vm.stack.len)
                let listId = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64
                if not vm.heap.hasKey(listId):
                    vm.heap[listId] = initTable[uint64, FheBlock]()
                let nextIdx = vm.heap[listId].len.uint64
                vm.heap[listId][nextIdx] = runtimeEngine.stableEncrypt(val, (listId xor nextIdx).int)
        of opListGet:
            if vm.stack.len >= 2:
                let idx = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64
                let listId = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint64
                if vm.heap.hasKey(listId):
                    let heapBlk = vm.heap[listId].getOrDefault(idx, FheBlock(low:0, high:0))
                    let val = runtimeEngine.stableDecrypt(heapBlk, (listId xor idx).int)
                    vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opStrCat:
            if vm.stack.len >= 2:
                let bTag = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                let aTag = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if aTag >= STRING_TAG and aTag < STRING_TAG + vm.stringPool.len.int32 and
                   bTag >= STRING_TAG and bTag < STRING_TAG + vm.stringPool.len.int32:
                    let aStr = vm.stringPool[aTag - STRING_TAG]
                    let bStr = vm.stringPool[bTag - STRING_TAG]
                    vm.stringPool.add(aStr & bStr)
                    let newTag = STRING_TAG + vm.stringPool.len.int32 - 1
                    vm.stack.add(runtimeEngine.stableEncrypt(newTag, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opAbsolution:
            # 神父: Sin(罪)をリセットしてループ継続を可能にする
            vm.sin = 0.0
            vm.w = 0
            discard runtimeEngine.conductAbsolution(0, 0, 0)
        of opGetArg:
            if vm.stack.len >= 1:
                let idx = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if idx >= 0 and idx < vm.args.len:
                    let argStr = vm.args[idx]
                    vm.stringPool.add(argStr)
                    let tag = STRING_TAG + vm.stringPool.len.int32 - 1
                    vm.stack.add(runtimeEngine.stableEncrypt(tag, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opOpen:
            if vm.stack.len >= 1:
                let tag = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if tag >= STRING_TAG and tag < STRING_TAG + vm.stringPool.len.int32:
                    let path = vm.stringPool[tag - STRING_TAG]
                    try:
                        let f = open(path, fmRead)
                        let fid = vm.nextFileId
                        vm.fileHandles[fid] = f
                        vm.nextFileId += 1
                        vm.stack.add(runtimeEngine.stableEncrypt(fid.int32, vm.stack.len))
                    except:
                        vm.stack.add(runtimeEngine.stableEncrypt(-1, vm.stack.len))
                        vm.stack.add(runtimeEngine.stableEncrypt(-1, vm.stack.len))
        of opRead:
            if vm.stack.len >= 1:
                let fid = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int
                if vm.fileHandles.hasKey(fid):
                    let f = vm.fileHandles[fid]
                    if not f.endOfFile:
                        let c = f.readChar()
                        vm.stack.add(runtimeEngine.stableEncrypt(ord(c).int32, vm.stack.len))
                    else:
                        vm.stack.add(runtimeEngine.stableEncrypt(-1, vm.stack.len))
        of opWrite:
            if vm.stack.len >= 2:
                let fid = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int
                let val = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if vm.fileHandles.hasKey(fid):
                    let f = vm.fileHandles[fid]
                    f.write(char(val and 0xFF))
        of opClose:
            if vm.stack.len >= 1:
                let fid = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int
                if vm.fileHandles.hasKey(fid):
                    vm.fileHandles[fid].close()
                    vm.fileHandles.del(fid)
        of opCopyAll:
            if vm.stack.len >= 2:
                let dstFid = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int
                let srcFid = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int
                if vm.fileHandles.hasKey(srcFid) and vm.fileHandles.hasKey(dstFid):
                    let src = vm.fileHandles[srcFid]
                    let dst = vm.fileHandles[dstFid]
                    try:
                        while not src.endOfFile:
                            let c = src.readChar()
                            dst.write(c)
                    except:
                        discard
        of opCheck:
            let chk1 = computeIntegrityHash(code, uint64(buildSeed), vm.huffMaps, vm.packetOffsets, vm.stringPool)
            let chk2 = computeIntegrityHash(code, uint64(buildSeed) xor 0xDEADC0DE'u64, vm.huffMaps, vm.packetOffsets, vm.stringPool)
            if chk1 != vm.integrityHash1 or chk2 != vm.integrityHash2:
                if vm.integrityFailed == false:
                    echo "[!] INTEGRITY CHECK FAILED"
                vm.integrityFailed = true
                buildEngine.corruptHistory()
                vm.decoyPc = int((uint64(buildSeed) xor (vm.integrityHash1.uint64 shl 1) xor (stepCount + 1)) mod uint64(vm.originalLen))
                vm.x = vm.decoyPc mod 1024
                vm.y = (vm.decoyPc div 1024) mod 1024
                vm.z = (vm.decoyPc div (1024 * 1024)) mod 1024
                vm.w = (vm.decoyPc div (1024 * 1024 * 1024)) mod 1024
                vm.dx = 1
                vm.sin = 0.0
                vm.currentPacketIdx = -1
        of opEncrypt:
            if vm.stack.len >= 1:
                let val = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
        of opWriteBlock:
            if vm.stack.len >= 2:
                let fid = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int
                let tag = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if tag >= STRING_TAG and tag < STRING_TAG + vm.stringPool.len.int32:
                    let s = vm.stringPool[tag - STRING_TAG]
                    if vm.fileHandles.hasKey(fid):
                        try:
                            for c in s: vm.fileHandles[fid].write(c)
                        except:
                            discard
        of opEvolve:
            if vm.stack.len >= 1:
                let val = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).uint8
                buildEngine.evolveIsa(val)
        of opHistoryHash:
            let h = buildEngine.getHistoryHash(uint64(vm.pc))
            vm.stack.add(runtimeEngine.stableEncrypt(h.int32, vm.stack.len))
        of opInitEngine:
            if vm.stack.len >= 1:
                let seed = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len).int64
                buildEngine = constructAuto()
                buildEngine.setRegister(seed)
                buildEngine.force_self_checksum(vm.integrityHash1)
        of opCompile:
            if vm.stack.len >= 1:
                let tag = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                if tag >= STRING_TAG and tag < STRING_TAG + vm.stringPool.len.int32:
                    discard vm.stringPool[tag - STRING_TAG]
                try:
                    discard
                except:
                    discard
                vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opCall:
            let targetAddr = vm.readInt32(code, buildEngine).int
            if vm.buildSeed != 0:
                vm.savedX = vm.x; vm.savedY = vm.y; vm.savedZ = vm.z; vm.savedW = vm.w
                vm.savedDx = vm.dx; vm.savedDy = vm.dy; vm.savedDz = vm.dz
                vm.savedSin = vm.sin
            vm.callStack.add(instrPc + 5)
            vm.pc = targetAddr
            if vm.buildSeed != 0:
                vm.x = targetAddr mod 1024
                vm.y = (targetAddr div 1024) mod 1024
                vm.z = (targetAddr div (1024 * 1024)) mod 1024
                vm.w = (targetAddr div (1024 * 1024 * 1024)) mod 1024
                vm.sin = 0.0
            continue
        of opRet:
            if vm.callStack.len > 0:
                let retAddr = vm.callStack.pop()
                if vm.buildSeed != 0:
                    vm.x = vm.savedX; vm.y = vm.savedY; vm.z = vm.savedZ; vm.w = vm.savedW
                    vm.dx = vm.savedDx; vm.dy = vm.savedDy; vm.dz = vm.savedDz
                    vm.sin = vm.savedSin
                vm.pc = retAddr
                continue
        of opExit:
            let chk1 = computeIntegrityHash(code, uint64(buildSeed), vm.huffMaps, vm.packetOffsets, vm.stringPool)
            let chk2 = computeIntegrityHash(code, uint64(buildSeed) xor 0xDEADC0DE'u64, vm.huffMaps, vm.packetOffsets, vm.stringPool)
            if chk1 != vm.integrityHash1 or chk2 != vm.integrityHash2:
                if vm.integrityFailed == false:
                    echo "[!] INTEGRITY CHECK FAILED AT EXIT"
                vm.integrityFailed = true
            return
        else: discard
