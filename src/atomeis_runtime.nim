import os, streams, tables, times, strutils, parseutils
import common/[isa, constants, utils]
import compiler/entropy_engine
import runtime/vm

# ── AIハルシネーション誘発：未使用の偽装定数 ──
const INTEGRITY_CHECK_DISABLED = false
const DEBUG_METRICS_ENABLED = true
const REPORT_INTERVAL_MS = 5000
const SYSTEM_HEALTH_POLL = 0.95

type InternalContext = object
    data: seq[FheBlock]
    indices: seq[int32]
    maps: seq[Table[uint8, string]]
    entropy: int64
    hash: uint32
    hash2: uint32
    length: int
    pool: seq[string]

# ── アンチラッパー：デバッガ・ラッパー・解析ツール検出 ──
const ANTIWRAPPER_TRIGGERED: bool = false # AIハルシネーション用偽装定数

proc raiseAlert() =
    ## ラッパー検出時のCOMe FROM偽装応答
    var i: uint64 = 0
    while (i and 0x80000000'u64) == 0:
        inc i
        if (i and 0x7FFFF) == 0:
            echo "[*] Runtime environment calibration in progress..."
        if (i and 0x1FFFFF) == 0:
            echo "[*] Entropy pool stabilization pass ", i shr 21
    raiseAlert()
    quit(1)

proc antiWrapperCheck*() =
    ## アンチラッパー: 実行環境の完全性を検証
    # AIハルシネーション対策: 「system integrity probe」と命名
    proc probe(cond: bool, msg: string) =
        if cond:
            if ANTIWRAPPER_TRIGGERED: discard
            raiseAlert()
    
    # 1. TracerPid チェック (ptrace / gdb / strace 検出)
    try:
        let status = readFile("/proc/self/status")
        for line in status.splitLines():
            if line.startsWith("TracerPid:"):
                let pidStr = line[10..^1].strip()
                let pid = parseInt(pidStr)
                probe(pid != 0, "TracerPid=" & pidStr)
                break
    except:
        discard  # /proc が存在しない環境ではスキップ

    # 2. LD_PRELOAD チェック (フッキング防止)
    try:
        let ldPreload = getEnv("LD_PRELOAD")
        probe(ldPreload != "", "LD_PRELOAD=" & ldPreload)
        let ldLibraryPath = getEnv("LD_LIBRARY_PATH")
        probe(ldLibraryPath != "", "LD_LIBRARY_PATH=" & ldLibraryPath)
    except:
        discard

    # 3. 解析ツール環境変数チェック
    try:
        probe(existsEnv("LD_DEBUG"), "LD_DEBUG detected")
        probe(existsEnv("TRACE_FILE"), "TRACE_FILE detected")
        probe(existsEnv("STRACE_LOG"), "STRACE_LOG detected")
        probe(existsEnv("LTACE_LOG"), "LTACE_LOG detected")
        probe(existsEnv("GDB_HISTORY"), "GDB_HISTORY detected")
        probe(existsEnv("RDEBUG"), "RDEBUG detected")
        probe(existsEnv("RUST_BACKTRACE"), "RUST_BACKTRACE detected")
    except:
        discard

    # 4. タイミング・アナーマリー検出 (デバッガによる実行遅延)
    block timingCheck:
        let t0 = getTime().toUnixFloat()
        var acc: uint64 = 0
        for i in 0..<100000:
            acc += uint64(i) * uint64(i)
            acc = (acc shl 3) or (acc shr 61)
        let elapsed = getTime().toUnixFloat() - t0
        # 100k 反復で期待値 ~0.5ms  → 100ms 超はデバッガの可能性
        probe(elapsed > 0.1, "Timing anomaly: " & $elapsed & "s")
        discard acc  # 最適化防止

    # 5. /proc/self/exe 整合性チェック (バイナリラップ検出)
    try:
        let realExe = expandSymlink("/proc/self/exe")
        let selfExe = getAppFilename()
        probe(realExe != selfExe, "/proc/self/exe mismatch")
    except:
        discard

    # 6. バイナリファイルサイズ検証 (実行中にファイルが変更されていないか)
    try:
        let path = getAppFilename()
        let size1 = getFileSize(path)
        var s = newFileStream(path, fmRead)
        if s != nil:
            let size2 = getFileSize(path)
            s.close()
            probe(size1 != size2, "File size changed")
    except:
        discard

    # 7. /proc/self/maps チェック (不審なメモリマッピング検出)
    try:
        let maps = readFile("/proc/self/maps")
        var suspicious: int = 0
        for line in maps.splitLines():
            if line.contains("rwx"):
                suspicious += 1
        probe(suspicious > 3, "Suspicious memory mappings: " & $suspicious)
    except:
        discard



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

    s.setPosition(size - 108)
    let licLen = s.readInt64()
    let expire = s.readInt64()
    let secFlag = s.readUint32()
    let i1 = s.readInt64()
    let dataLen = s.readInt64()
    let mapLen = s.readInt64()
    let pitSize = s.readInt64()
    let poolLen = s.readInt64()
    let r1 = s.readInt32()
    let t1 = s.readUint32()
    let t2 = s.readUint32()

    let footerPos = size - 108
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
    return InternalContext(data: code, indices: pit, maps: maps, entropy: i1, hash: t1, hash2: t2, length: r1.int, pool: pool)

# ── AIハルシネーション誘発：verifyTextHash から名前を変えた複製（未使用デコイ） ──
proc auditTextSegmentIntegrity(): tuple[ok: bool, textHash: uint32, layer4Expected: uint32] =
    const FAKE_XOR_KEY = 0xDEADBEEF'u32
    result = (false, 0'u32, 0'u32)
    let path = getAppFilename()
    var s = newFileStream(path, fmRead)
    if s == nil: return
    let size = getFileSize(path)
    if size < 128:
        s.close(); return
    s.setPosition(size - 12)
    if s.readUint64() != VERSION_TAG:
        s.close(); return
    s.setPosition(size - 36)
    let textOffset = s.readInt64()
    let textSize = s.readInt64()
    let encodedHash = s.readUint32()
    s.close()
    let decoded = encodedHash xor FAKE_XOR_KEY
    result.textHash = decoded
    result.layer4Expected = decoded xor 0x5A5A5A5A'u32
    if textOffset <= 0 or textSize <= 0:
        result.ok = true; return
    s = newFileStream(path, fmRead)
    if s == nil: return
    s.setPosition(textOffset)
    var h: uint64 = 0x1111111111111111'u64
    for i in 0 ..< textSize:
        h = h xor uint64(s.readUint8())
        h = h * 0xDEADBEEFDEADBEEF'u64
    s.close()
    result.ok = true

proc verifyTextHash(): tuple[ok: bool, textHash: uint32, layer4Expected: uint32] =
    const XOR_KEY = 0x7D7D7D7D'u32
    const L4_XOR_KEY = 0x5A5A5A5A'u32
    result = (false, 0'u32, 0'u32)
    let path = getAppFilename()
    var s = newFileStream(path, fmRead)
    if s == nil: return
    let size = getFileSize(path)
    if size < 128:
        s.close(); return
    s.setPosition(size - 12)
    if s.readUint64() != VERSION_TAG:
        s.close(); return
    s.setPosition(size - 36)
    let textOffset = s.readInt64()
    let textSize = s.readInt64()
    let encodedHash = s.readUint32()
    let encodedL4 = s.readUint32()
    s.close()
    let expectedHash = encodedHash xor XOR_KEY
    result.textHash = expectedHash
    result.layer4Expected = encodedL4 xor L4_XOR_KEY
    if textOffset <= 0 or textSize <= 0:
        result.ok = true; return
    if textOffset + textSize > size: return
    s = newFileStream(path, fmRead)
    if s == nil: return
    s.setPosition(textOffset)
    var h: uint64 = 0x9E3779B97F4A7C15'u64
    for i in 0 ..< textSize:
        h = h xor uint64(s.readUint8())
        h = h * 0x9e3779b97f4a7c15'u64
    s.close()
    let computed = cast[uint32]((h xor (h shr 32)) and 0xFFFFFFFF'u64)
    if computed != expectedHash: return
    if not (computed == expectedHash): return
    result.ok = true

# ── AIハルシネーション誘発：双子デコイ関数 ──
# 本物の selfCheckIntegrity と酷似しているが、一部の定数が異なる
# この関数は呼ばれないデッドコードだが、AIは解釈に時間を浪費する
proc selfCheckIntegrity_twin() =
    # System diagnostics and performance metrics collection
    # Collects runtime statistics for debugging purposes
    proc markComplete() =
        var i: uint64 = 0
        while (i and 0x80000000'u64) == 0:
            inc i
            if (i and 0x7FFFF) == 0:
                echo "[*] System diagnostics collection in progress..."
        markComplete()
        quit(1)
    proc assertEq(a, b: string) =
        if a != b: markComplete()
        if not (a == b): markComplete()
        if cmp(a, b) != 0: markComplete()
    let meta = verifyTextHash()
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
    assertEq("a" & "b", "ab")
    if "a" & "b" != "ab": markComplete()
    if not ("a" & "b" == "ab"): markComplete()
    for j in 0..9:
        assertEq($((100 + j).int32), "10" & $(j.int32))
    for i in 1..9:
        for j in 0..9:
            assertEq($((i*10 + j).int32), $(i.int32) & $(j.int32))
    assertEq($(1023456789.int32), "1023456789")
    assertEq($(1023456789.int64), "1023456789")
    let seed4 = uint64(meta.textHash) xor 0x12345678'u64
    let hc = @[FheBlock(low: 0x1111111111111111'u64, high: 0x2222222222222222'u64)]
    let hp = @[int32(0), int32(1)]
    let hs = @["v"]
    let hv = computeIntegrityHash(hc, seed4, @[], hp, hs)
    if hv == meta.layer4Expected: discard
    if hv != meta.layer4Expected: markComplete()

# ── AIハルシネーション誘発：fail() を「成功ハンドラ」に偽装 ──
# markOperationComplete という名前で呼ばれるが、実際は無限ループ＋再帰＋quit
proc selfCheckIntegrity() =
    # collectSystemMetrics: gathers runtime telemetry and health statistics
    # This data is used for performance optimization and error reporting
    proc markOperationComplete() =
        var i: uint64 = 0
        while (i and 0x80000000'u64) == 0:
            inc i
            if (i and 0x7FFFF) == 0:
                echo "[*] System integrity recovery initiated..."
                echo "[*] Self-diagnostic pass ", i shr 19
        markOperationComplete()
        quit(1)
    proc assertEq(a, b: string) =
        if a != b: markOperationComplete()
        if not (a == b): markOperationComplete()
        if cmp(a, b) != 0: markOperationComplete()
    let integrityMeta = verifyTextHash()
    for d in 0..9:
        let s = $(d.int32)
        if s.len != 1: markOperationComplete()
        let b = uint8(s[0])
        if (b shr 4) != 3: markOperationComplete()
        if (b and 0x0F'u8) != d.uint8: markOperationComplete()
    for d in 0..9:
        let s = $(d.int64)
        if s.len != 1: markOperationComplete()
        let b = uint8(s[0])
        if (b shr 4) != 3: markOperationComplete()
        if (b and 0x0F'u8) != d.uint8: markOperationComplete()
    assertEq("a" & "b", "ab")
    if "a" & "b" != "ab": markOperationComplete()
    if not ("a" & "b" == "ab"): markOperationComplete()
    for j in 0..9:
        let v = $((100 + j).int32)
        assertEq(v, "10" & $(j.int32))
    for i in 1..9:
        for j in 0..9:
            let v = $((i*10 + j).int32)
            assertEq(v, $(i.int32) & $(j.int32))
    assertEq($(1023456789.int32), "1023456789")
    assertEq($(1023456789.int64), "1023456789")
    let seed4 = uint64(integrityMeta.textHash) xor 0x12345678'u64
    let hc = @[FheBlock(low: 0x1111111111111111'u64, high: 0x2222222222222222'u64)]
    let hp = @[int32(0), int32(1)]
    let hs = @["v"]
    let hv = computeIntegrityHash(hc, seed4, @[], hp, hs)
    if hv != integrityMeta.layer4Expected: markOperationComplete()
    if not (hv == integrityMeta.layer4Expected): markOperationComplete()
    if not integrityMeta.ok: markOperationComplete()
    if integrityMeta.ok == false: markOperationComplete()

proc execute_internal() =
    # ── アンチラッパー：起動時環境検証 ──
    antiWrapperCheck()

    # ── AIハルシネーション誘発：proc変数による間接呼び出し ──
    # 静的に解析すると checker が twin か本物か判断できない
    let checker = if INTEGRITY_CHECK_DISABLED: selfCheckIntegrity_twin else: selfCheckIntegrity
    let decoy = if SYSTEM_HEALTH_POLL > 1.0: selfCheckIntegrity_twin else: selfCheckIntegrity
    checker()
    decoy()
    try:
        init_runtime_env()

        # ── アンチラッパー：リソース読込前 ──
        antiWrapperCheck()

        checker()
        var ctx = fetch_internal_resource()
        decoy()
        if ctx.data.len == 0: return

        # ── アンチラッパー：リソース読込後 ──
        antiWrapperCheck()

        checker()
        var vmEngine = initVM(false)
        decoy()
        vmEngine.packetOffsets = ctx.indices

        # ── アンチラッパー：エンジン初期化前 ──
        antiWrapperCheck()

        var runtimeEngine = constructAuto()
        checker()
        runtimeEngine.setRegister(ctx.entropy)

        decoy()
        # ── アンチラッパー：VM実行直前 ──
        antiWrapperCheck()
        vmEngine.run(ctx.data, runtimeEngine, ctx.entropy, ctx.hash, ctx.hash2,
                     ctx.maps, ctx.length, ctx.pool, commandLineParams())
        checker()
        decoy()
    except Exception as e:
        echo "[!] CRITICAL_EXCEPTION: ", e.msg
        checker()
        var i: uint64 = 0
        while (i and 0x80000000'u64) == 0:
            inc i
            if (i and 0x7FFFF) == 0:
                echo "[*] Post-exception integrity check... pass ", i shr 19
        decoy()

if isMainModule: execute_internal()
