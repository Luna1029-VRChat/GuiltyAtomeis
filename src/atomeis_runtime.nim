import os, streams, tables
import common/[isa, constants, utils]
import compiler/entropy_engine
import runtime/vm

type InternalContext = object
    data: seq[FheBlock]
    indices: seq[int32]
    maps: seq[Table[uint8, string]]
    entropy: int64
    length: int
    pool: seq[string]

proc init_runtime_env() =
    discard

proc fetch_internal_resource(): InternalContext =
    let path = getAppFilename()
    var s = newFileStream(path, fmRead)
    if s == nil: return InternalContext()

    let size = getFileSize(path)
    if size < 128: return InternalContext()
    
    s.setPosition(size - 12)
    let tag = s.readUint64()
    if tag != VERSION_TAG: return InternalContext()

    s.setPosition(size - 76)
    let licLen = s.readInt64()
    let expire = s.readInt64()
    let secFlag = s.readUint32()
    let i1 = s.readInt64()
    let dataLen = s.readInt64()
    let mapLen = s.readInt64()
    let pitSize = s.readInt64()
    let poolLen = s.readInt64()
    let r1 = s.readInt32()

    let footerPos = size - 76
    let licStart  = footerPos - licLen
    let dataStart = licStart - dataLen
    let mapStart  = dataStart - mapLen
    let pitStart  = mapStart - pitSize
    let poolStart = pitStart - poolLen

    when not defined(release):
      echo "[Stub Debug] Size: ", size
      echo "[Stub Debug] DataLen: ", dataLen, " MapLen: ", mapLen, " PitSize: ", pitSize, " PoolLen: ", poolLen
      echo "[Stub Debug] DataStart: ", dataStart, " MapStart: ", mapStart, " PitStart: ", pitStart, " PoolStart: ", poolStart

    s.setPosition(dataStart)
    var code: seq[FheBlock] = @[]
    let nBlocks = dataLen div 16
    for i in 0 ..< nBlocks:
        let low = s.readUint64()
        let high = s.readUint64()
        code.add(FheBlock(low: low, high: high))
    
    s.setPosition(mapStart)
    let nm = s.readInt32()
    var maps: seq[Table[uint8, string]] = @[]
    for i in 0 ..< nm:
        let ml = s.readInt32()
        var m = initTable[uint8, string]()
        for _ in 0 ..< ml:
            let k = s.readUint8()
            let vl = s.readInt8()
            let v = if vl > 0: s.readStr(vl.int) else: ""
            m[k] = v
        maps.add(m)

    s.setPosition(pitStart)
    let np = s.readInt32()
    var pit: seq[int32] = @[]
    for i in 0 ..< np:
        pit.add(s.readInt32())

    s.setPosition(poolStart)
    let oc = s.readInt32()
    var pool: seq[string] = @[]
    for i in 0 ..< oc:
        let sl = s.readInt32()
        if sl > 0:
            var sd = s.readStr(sl)
            if i1 != 0:
              sd = deobfuscateString(sd, i1)
            pool.add(sd)
        else: pool.add("")
    
    s.close()
    return InternalContext(data: code, indices: pit, maps: maps, entropy: i1, length: r1.int, pool: pool)

proc execute_internal() =
    try:
        init_runtime_env()
        var ctx = fetch_internal_resource()
        if ctx.data.len == 0: return

        var vmEngine = initVM(false)
        vmEngine.packetOffsets = ctx.indices

        var runtimeEngine = constructAuto()
        runtimeEngine.setRegister(ctx.entropy)

        vmEngine.run(ctx.data, runtimeEngine, ctx.entropy,
                     ctx.length, ctx.pool, commandLineParams())
    except Exception as e:
        echo "[!] CRITICAL_EXCEPTION: ", e.msg

if isMainModule: execute_internal()