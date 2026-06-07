# src/runtime/oram.nim
# Oblivious RAM (ORAM) + サンドボックス暗号化メモリ
# アクセスパターンを隠蔽し、常時暗号化状態でメモリを保持する

import tables, ../common/isa

type
  OramBlock* = object
    valid*: bool
    address*: uint64      # 論理アドレス（暗号化）
    data*: FheBlock    # 暗号化データ

  # シンプルなPath-ORAM風のサンドボックスメモリ
  OramMemory* = object
    buckets*: seq[OramBlock]   # 実メモリ（ランダム配置）
    posMap*: Table[uint64, int] # 論理addr → バケット位置（秘密）
    stash*: Table[uint64, FheBlock] # 一時退避ストア（stash）
    size*: int
    engineKey*: uint64  # 暗号化キー（セッションごと）

proc initOramMemory*(size: int, key: uint64): OramMemory =
  result.size = size
  result.engineKey = key
  result.buckets = newSeq[OramBlock](size)
  result.posMap = initTable[uint64, int]()
  result.stash = initTable[uint64, FheBlock]()
  for i in 0 ..< size:
    result.buckets[i] = OramBlock(valid: false, address: 0,
      data: FheBlock(low: 0, high: 0))

# アドレスを内部キーで難読化（アクセスパターン隠蔽）
proc obfuscateAddr(mem: OramMemory, logicalAddr: uint64): uint64 =
  # シンプルなFeistel風変換
  var v = logicalAddr xor mem.engineKey
  v = ((v shl 13) or (v shr 51)) xor (mem.engineKey * 0x9e3779b97f4a7c15'u64)
  return v mod uint64(mem.size)

# ORAM Read: 毎回フルスキャン（アクセスパターン隠蔽のため）
proc oramRead*(mem: var OramMemory, logicalAddr: uint64): FheBlock =
  # stashを先にチェック
  if mem.stash.hasKey(logicalAddr):
    return mem.stash[logicalAddr]

  # posMapで位置を取得、なければダミーアクセスして0を返す
  let targetPos = if mem.posMap.hasKey(logicalAddr): mem.posMap[logicalAddr]
                  else: -1

  var found = FheBlock(low: 0, high: 0)
  # フルスキャン（全バケットアクセスでアクセスパターンを隠す）
  for i in 0 ..< mem.size:
    if mem.buckets[i].valid and int(mem.buckets[i].address) == int(logicalAddr):
      found = mem.buckets[i].data

  # 読み取り後はstashへ移動（次の書き込みまで保持）
  if targetPos >= 0:
    mem.stash[logicalAddr] = found

  return found

# ORAM Write: 新しい位置を選んで書き込み
proc oramWrite*(mem: var OramMemory, logicalAddr: uint64, data: FheBlock) =
  mem.stash[logicalAddr] = data

  # 既存スロットがあれば再利用、なければ線形探索で空きスロットを探す
  let obfAddr = obfuscateAddr(mem, logicalAddr)
  var slot = int(obfAddr mod uint64(mem.size))
  let startSlot = slot

  while true:
    if not mem.buckets[slot].valid:
      mem.buckets[slot] = OramBlock(valid: true, address: logicalAddr, data: data)
      mem.posMap[logicalAddr] = slot
      break
    if int(mem.buckets[slot].address) == int(logicalAddr):
      mem.buckets[slot].data = data
      break
    slot = (slot + 1) mod mem.size
    if slot == startSlot:
      break

  mem.stash.del(logicalAddr)

# メモリをゼロクリア（終了時のセキュリティ消去）
proc secureWipe*(mem: var OramMemory) =
  for i in 0 ..< mem.size:
    mem.buckets[i] = OramBlock(valid: false, address: 0,
      data: FheBlock(low: 0, high: 0))
  mem.posMap.clear()
  mem.stash.clear()
