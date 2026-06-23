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
    packetOffsets*: seq[int32]
    originalLen*: int
    buildSeed*: int64
    currentPacketIdx*: int
    stringPool*: seq[string]
    captureBuffer*: seq[uint8]
    inputFeed*: seq[uint8]
    inputPtr*: int
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
    # FFI extern handler: proc(vm, runtimeEngine, externIndex)
    externHandler*: proc(vm: var VM, runtimeEngine: var AutonomousMalbolge, idx: int) {.nimcall.}
    # Heap bump allocation pointer
    heapNextAddr*: int



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
            bytes[i] = if vm.pc < code.len: code[vm.pc].low.uint8 else: 0'u8
            vm.pc += 1
        else:
            vm.pc = (vm.x + vm.y * 1024 + vm.z * 1024 * 1024 + vm.w * 1024 * 1024 * 1024) mod vm.originalLen
            if vm.pc < 0: vm.pc = abs(vm.pc)
            let pIdx = vm.pc div 16
            vm.fetchPacket(code, buildEngine, pIdx)
            let b = vm.isolationBuffer[vm.pc mod 16]
            bytes[i] = b
            vm.isolationBuffer[vm.pc mod 16] = opNoise.uint8
            vm.x = (vm.x + 1) mod 1024
            buildEngine.evolveIsa(b)
    return cast[int64](bytes)

proc readInt32(vm: var VM, code: seq[FheBlock], buildEngine: var AutonomousMalbolge): int32 =
    var bytes: array[4, uint8]
    if vm.buildSeed == 0:
        for i in 0..3:
            bytes[i] = if vm.pc < code.len: code[vm.pc].low.uint8 else: 0'u8
            vm.pc += 1
        return cast[int32](bytes)
    for i in 0..3:
        # 常に最新の座標から pc を計算
        vm.pc = (vm.x + vm.y * 1024 + vm.z * 1024 * 1024 + vm.w * 1024 * 1024 * 1024) mod vm.originalLen
        if vm.pc < 0: vm.pc = abs(vm.pc)
        let pIdx = vm.pc div 16
        vm.fetchPacket(code, buildEngine, pIdx)
        let b = vm.isolationBuffer[vm.pc mod 16]
        bytes[i] = b
        vm.isolationBuffer[vm.pc mod 16] = opNoise.uint8
        vm.x = (vm.x + 1) mod 1024
        buildEngine.evolveIsa(b)
    return cast[int32](bytes)

proc run*(vm: var VM, code: seq[FheBlock], runtimeEngine: var AutonomousMalbolge,
          buildSeed: int64, originalLen: int,
          stringPool: seq[string] = @[], args: seq[string] = @[]) =

    vm.args = args
    vm.originalLen = originalLen
    vm.buildSeed = buildSeed
    vm.stringPool = stringPool
    var buildEngine = constructAuto()

    # Thue ISA Shuffler 初期化
    if buildSeed != 0:
      let thueSeed = ThueSeed(uint64(buildSeed)) + 0x9E3779B9'u64
      vm.thueShuffler = initThueShuffler(thueSeed)

    # ORAM 初期化
    let oramKey = uint64(buildSeed) xor 0x0B1B10C0'u64
    vm.oramMem = initOramMemory(1024, oramKey)
    vm.debugData = newSeq[int32](1024)
    vm.heapNextAddr = 4096

    # buildEngine のレジスタ状態を compile時と合わせる
    buildEngine.setRegister(buildSeed)

    let isSalvation = vm.privileged
    var stepCount: uint64 = 0

    while vm.pc < vm.originalLen:
        inc stepCount

        # --- 4D 迷宮座標 → 線形PC マッピング ---
        if vm.buildSeed != 0:
          vm.pc = (vm.x + vm.y * 1024 + vm.z * 1024 * 1024 + vm.w * 1024 * 1024 * 1024) mod vm.originalLen
          if vm.pc < 0: vm.pc = abs(vm.pc)

        if vm.buildSeed != 0:
            let pIdx = vm.pc div 16
            if pIdx != vm.currentPacketIdx:
                vm.fetchPacket(code, buildEngine, pIdx)
                vm.currentPacketIdx = pIdx

        var instrPc = vm.pc
        var instr: OpCode
        if vm.buildSeed == 0:
            let b = if instrPc < code.len: code[instrPc].low.uint8 else: 0'u8
            vm.pc = instrPc + 1
            instr = cast[OpCode](b)
        else:
            let localPc = instrPc mod 16
            instr = cast[OpCode](vm.isolationBuffer[localPc])
            vm.isolationBuffer[localPc] = opNoise.uint8
            if not vm.privileged:
                vm.sin = vm.sin + cast[float64](runtimeEngine.generateTrueSpice() and 0xFFFF) / 65535.0
                vm.w = (vm.w + int(vm.sin)) mod 1024
                if vm.w < 0: vm.w = abs(vm.w) mod 1024
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
        of opAdd, opSub, opMul, opDiv, opMod, opXor, opAnd, opOr, opShl, opShr, opEq, opNe, opLt, opGt, opLe, opGe:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let bBlk = vm.stack.pop()
                let b = runtimeEngine.stableDecrypt(bBlk, targetLen + 1)
                let aBlk = vm.stack.pop()
                let a = runtimeEngine.stableDecrypt(aBlk, targetLen)
                var res: int32 = 0
                case instr
                of opAdd: res = a + b
                of opSub: res = a - b
                of opMul: res = a * b
                of opDiv: res = if b != 0: a div b else: 0
                of opMod: res = if b != 0: a mod b else: 0
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
                let targetLen = vm.stack.len - 2
                let bBlk = vm.stack.pop()
                let bBits = runtimeEngine.stableDecrypt(bBlk, targetLen + 1)
                let aBlk = vm.stack.pop()
                let aBits = runtimeEngine.stableDecrypt(aBlk, targetLen)
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
                let targetLen = vm.stack.len - 4
                let bHiBlk = vm.stack.pop()
                let bHi = runtimeEngine.stableDecrypt(bHiBlk, targetLen + 3)
                let bLoBlk = vm.stack.pop()
                let bLo = runtimeEngine.stableDecrypt(bLoBlk, targetLen + 2)
                let aHiBlk = vm.stack.pop()
                let aHi = runtimeEngine.stableDecrypt(aHiBlk, targetLen + 1)
                let aLoBlk = vm.stack.pop()
                let aLo = runtimeEngine.stableDecrypt(aLoBlk, targetLen)
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
                let targetLen = vm.stack.len - 3
                let rawValBlk = vm.stack.pop()
                let val = runtimeEngine.stableDecrypt(rawValBlk, targetLen + 2)
                let keyBlk = vm.stack.pop()
                let key = runtimeEngine.stableDecrypt(keyBlk, targetLen + 1).uint64
                let mapIdBlk = vm.stack.pop()
                let mapId = (runtimeEngine.stableDecrypt(mapIdBlk, targetLen).uint64) and 0x7FFFFFFF
                if vm.heap.hasKey(mapId): 
                    vm.heap[mapId][key] = runtimeEngine.stableEncrypt(val, (mapId xor key).int)
        of opMapGet:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let keyBlk = vm.stack.pop()
                let key = runtimeEngine.stableDecrypt(keyBlk, targetLen + 1).uint64
                let mapIdBlk = vm.stack.pop()
                let mapId = (runtimeEngine.stableDecrypt(mapIdBlk, targetLen).uint64) and 0x7FFFFFFF
                if vm.heap.hasKey(mapId): 
                    let heapBlk = vm.heap[mapId].getOrDefault(key, FheBlock(low:0, high:0))
                    let val = runtimeEngine.stableDecrypt(heapBlk, (mapId xor key).int)
                    vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opStrEq:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let bTagBlk = vm.stack.pop()
                let bTag = runtimeEngine.stableDecrypt(bTagBlk, targetLen + 1)
                let aTagBlk = vm.stack.pop()
                let aTag = runtimeEngine.stableDecrypt(aTagBlk, targetLen)
                var res: int32 = 0
                if aTag >= STRING_TAG and aTag < STRING_TAG + vm.stringPool.len.int32 and
                   bTag >= STRING_TAG and bTag < STRING_TAG + vm.stringPool.len.int32:
                    let aStr = vm.stringPool[aTag - STRING_TAG]
                    let bStr = vm.stringPool[bTag - STRING_TAG]
                    res = if aStr == bStr: 1 else: 0
                else:
                    res = if aTag == bTag: 1 else: 0
                vm.stack.add(runtimeEngine.stableEncrypt(res, vm.stack.len))
        of opStrLen, opArrayLen:
            if vm.stack.len >= 1:
                let targetLen = vm.stack.len - 1
                let arrBlk = vm.stack.pop()
                let arrVal = runtimeEngine.stableDecrypt(arrBlk, targetLen)
                if arrVal >= STRING_TAG and arrVal < STRING_TAG + vm.stringPool.len.int32:
                    let s = vm.stringPool[arrVal - STRING_TAG]
                    vm.stack.add(runtimeEngine.stableEncrypt(s.len.int32, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opStrGet, opArrayGet:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let idxBlk = vm.stack.pop()
                let idx = runtimeEngine.stableDecrypt(idxBlk, targetLen + 1).int
                let arrBlk = vm.stack.pop()
                let arrVal = runtimeEngine.stableDecrypt(arrBlk, targetLen)
                if arrVal >= STRING_TAG and arrVal < STRING_TAG + vm.stringPool.len.int32:
                    let s = vm.stringPool[arrVal - STRING_TAG]
                    let ch = if idx >= 0 and idx < s.len: ord(s[idx]).int32 else: 0
                    vm.stack.add(runtimeEngine.stableEncrypt(ch, vm.stack.len))
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
                let targetLen = vm.stack.len - 2
                let valBlk = vm.stack.pop()
                let val = runtimeEngine.stableDecrypt(valBlk, targetLen + 1)
                let listIdBlk = vm.stack.pop()
                let listId = runtimeEngine.stableDecrypt(listIdBlk, targetLen).uint64
                if not vm.heap.hasKey(listId):
                    vm.heap[listId] = initTable[uint64, FheBlock]()
                let nextIdx = vm.heap[listId].len.uint64
                vm.heap[listId][nextIdx] = runtimeEngine.stableEncrypt(val, (listId xor nextIdx).int)
        of opListGet:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let idxBlk = vm.stack.pop()
                let idx = runtimeEngine.stableDecrypt(idxBlk, targetLen + 1).uint64
                let listIdBlk = vm.stack.pop()
                let listId = runtimeEngine.stableDecrypt(listIdBlk, targetLen).uint64
                if vm.heap.hasKey(listId):
                    let heapBlk = vm.heap[listId].getOrDefault(idx, FheBlock(low:0, high:0))
                    let val = runtimeEngine.stableDecrypt(heapBlk, (listId xor idx).int)
                    vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
                else:
                    vm.stack.add(runtimeEngine.stableEncrypt(0, vm.stack.len))
        of opStrCat:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let bTagBlk = vm.stack.pop()
                let bTag = runtimeEngine.stableDecrypt(bTagBlk, targetLen + 1)
                let aTagBlk = vm.stack.pop()
                let aTag = runtimeEngine.stableDecrypt(aTagBlk, targetLen)
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
                let targetLen = vm.stack.len - 2
                let fidBlk = vm.stack.pop()
                let fid = runtimeEngine.stableDecrypt(fidBlk, targetLen + 1).int
                let valBlk = vm.stack.pop()
                let val = runtimeEngine.stableDecrypt(valBlk, targetLen)
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
                let targetLen = vm.stack.len - 2
                let dstFidBlk = vm.stack.pop()
                let dstFid = runtimeEngine.stableDecrypt(dstFidBlk, targetLen + 1).int
                let srcFidBlk = vm.stack.pop()
                let srcFid = runtimeEngine.stableDecrypt(srcFidBlk, targetLen).int
                if vm.fileHandles.hasKey(srcFid) and vm.fileHandles.hasKey(dstFid):
                    let src = vm.fileHandles[srcFid]
                    let dst = vm.fileHandles[dstFid]
                    try:
                        while not src.endOfFile:
                            let c = src.readChar()
                            dst.write(c)
                    except:
                        discard
        of opEncrypt:
            if vm.stack.len >= 1:
                let val = runtimeEngine.stableDecrypt(vm.stack.pop(), vm.stack.len)
                vm.stack.add(runtimeEngine.stableEncrypt(val, vm.stack.len))
        of opWriteBlock:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let fidBlk = vm.stack.pop()
                let fid = runtimeEngine.stableDecrypt(fidBlk, targetLen + 1).int
                let tagBlk = vm.stack.pop()
                let tag = runtimeEngine.stableDecrypt(tagBlk, targetLen)
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
        of opFFICall:
            let externIdx = vm.readInt32(code, buildEngine).int
            if vm.externHandler != nil:
                vm.externHandler(vm, runtimeEngine, externIdx)
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
        of opRet, opReturn:
            if vm.callStack.len > 0:
                let retAddr = vm.callStack.pop()
                if vm.buildSeed != 0:
                    vm.x = vm.savedX; vm.y = vm.savedY; vm.z = vm.savedZ; vm.w = vm.savedW
                    vm.dx = vm.savedDx; vm.dy = vm.savedDy; vm.dz = vm.savedDz
                    vm.sin = vm.savedSin
                vm.pc = retAddr
                continue
        of opPushBool:
            let b = vm.readInt32(code, buildEngine)
            vm.stack.add(runtimeEngine.stableEncrypt(b, vm.stack.len))
        of opAlloc:
            if vm.stack.len >= 1:
                let sizeBlk = vm.stack.pop()
                let byteSize = runtimeEngine.stableDecrypt(sizeBlk, vm.stack.len).int
                let slotCount = max(1, byteSize div 4 + (if byteSize mod 4 != 0: 1 else: 0))
                let heapAddr = vm.heapNextAddr
                vm.heapNextAddr += slotCount
                if vm.heapNextAddr >= vm.debugData.len:
                    vm.debugData.setLen(vm.heapNextAddr + 1024)
                vm.stack.add(runtimeEngine.stableEncrypt(heapAddr.int32, vm.stack.len))
        of opFree:
            if vm.stack.len >= 1:
                discard vm.stack.pop()
        of opPtrRead:
            if vm.stack.len >= 2:
                let targetLen = vm.stack.len - 2
                let offsetBlk = vm.stack.pop()
                let byteOffset = runtimeEngine.stableDecrypt(offsetBlk, targetLen + 1).int
                let baseBlk = vm.stack.pop()
                let baseSlot = runtimeEngine.stableDecrypt(baseBlk, targetLen).int
                let slotIdx = baseSlot + byteOffset div 4
                if slotIdx >= 0:
                    if vm.buildSeed == 0:
                        let raw = if slotIdx < vm.debugData.len: vm.debugData[slotIdx] else: 0
                        vm.stack.add(runtimeEngine.stableEncrypt(raw, vm.stack.len))
                    else:
                        let ramBlk = vm.oramMem.oramRead(uint64(slotIdx))
                        let v = runtimeEngine.stableDecrypt(ramBlk, slotIdx)
                        vm.stack.add(runtimeEngine.stableEncrypt(v, vm.stack.len))
        of opPtrWrite:
            if vm.stack.len >= 3:
                let targetLen = vm.stack.len - 3
                let valBlk = vm.stack.pop()
                let val = runtimeEngine.stableDecrypt(valBlk, targetLen + 2)
                let offsetBlk = vm.stack.pop()
                let byteOffset = runtimeEngine.stableDecrypt(offsetBlk, targetLen + 1).int
                let baseBlk = vm.stack.pop()
                let baseSlot = runtimeEngine.stableDecrypt(baseBlk, targetLen).int
                let slotIdx = baseSlot + byteOffset div 4
                if slotIdx >= 0:
                    if vm.buildSeed == 0:
                        if slotIdx >= vm.debugData.len:
                            vm.debugData.setLen(slotIdx + 1024)
                        vm.debugData[slotIdx] = val
                    else:
                        let reencBlk = runtimeEngine.stableEncrypt(val, slotIdx)
                        vm.oramMem.oramWrite(uint64(slotIdx), reencBlk)
        of opAddr:
            discard
        of opExit:
            return
        else: discard
