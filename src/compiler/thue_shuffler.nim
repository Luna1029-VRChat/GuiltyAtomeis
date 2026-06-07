# src/compiler/thue_shuffler.nim
# Thueマシン方式によるISAシャッフルエンジン
# 毎命令ごとにThuレライティングルールを適用してISA対応表を書き換える
# これにより静的解析では命令の意味が解読不能になる

import random

type
  ThueLHS* = seq[uint8]   # 左辺パターン
  ThuRHS* = seq[uint8]   # 右辺（置換後）
  ThueRule* = tuple[lhs: ThueLHS, rhs: ThuRHS]
  ThueSeed* = uint64

  ThueShuffler* = object
    rules*: seq[ThueRule]
    # 現在のISAマッピング: 論理オペコード → 実際のバイト値
    encTable*: array[256, uint8]
    # 逆引き: 実際のバイト値 → 論理オペコード
    decTable*: array[256, uint8]
    step*: uint64
    seed*: ThueSeed

# 初期ISAマッピング（恒等変換）を作成
proc initIdentityMapping(s: var ThueShuffler) =
  for i in 0 ..< 256:
    s.encTable[i] = uint8(i)
    s.decTable[i] = uint8(i)

# シードからThueルールセットを生成
proc generateRules(seed: ThueSeed): seq[ThueRule] =
  var rng = initRand(int64(seed))
  result = @[]
  # 固定のルール群：これがThue風の書き換えルールとなる
  for _ in 0 ..< 16:
    let a = uint8(rng.rand(254) + 1)
    let b = uint8(rng.rand(254) + 1)
    if a != b:
      result.add((@[a], @[b]))  # a → b の置換

# ThueShuffler を初期化
proc initThueShuffler*(seed: ThueSeed): ThueShuffler =
  result.seed = seed
  result.step = 0
  initIdentityMapping(result)
  result.rules = generateRules(seed)

# 1ステップ：現在のルールを適用してISAテーブルをシャッフル
# 各命令実行後に呼び出す
proc applyStep*(s: var ThueShuffler) =
  inc s.step
  # stepとseedを組み合わせてどのルールを適用するか決定（決定論的）
  let ruleIdx = int((s.step xor s.seed) mod uint64(s.rules.len))
  let rule = s.rules[ruleIdx]

  if rule.lhs.len == 1 and rule.rhs.len == 1:
    let a = rule.lhs[0]
    let b = rule.rhs[0]
    # encTable内でaとbを交換
    for i in 0 ..< 256:
      if s.encTable[i] == a:
        s.encTable[i] = b
      elif s.encTable[i] == b:
        s.encTable[i] = a

    # decTableを再構築
    for i in 0 ..< 256:
      s.decTable[int(s.encTable[i])] = uint8(i)

# 論理オペコードを現在のISAマッピングで暗号化（エンコード）
proc encodeOp*(s: ThueShuffler, logicalOp: uint8): uint8 =
  s.encTable[int(logicalOp)]

# 実行時バイトを論理オペコードにデコード
proc decodeOp*(s: ThueShuffler, physicalByte: uint8): uint8 =
  s.decTable[int(physicalByte)]

# 指定したステップ数まで巻き戻し／進める
proc seek*(s: var ThueShuffler, targetStep: uint64) =
  if targetStep == s.step: return
  if targetStep < s.step:
    initIdentityMapping(s)
    s.step = 0
  for step in (s.step + 1) .. targetStep:
    let ruleIdx = int((step xor s.seed) mod uint64(s.rules.len))
    let rule = s.rules[ruleIdx]
    if rule.lhs.len == 1 and rule.rhs.len == 1:
      let a = rule.lhs[0]
      let b = rule.rhs[0]
      for i in 0 ..< 256:
        if s.encTable[i] == a:
          s.encTable[i] = b
        elif s.encTable[i] == b:
          s.encTable[i] = a
      for i in 0 ..< 256:
        s.decTable[int(s.encTable[i])] = uint8(i)
  s.step = targetStep

# デバッグ用：現在の状態をダンプ
proc dumpState*(s: ThueShuffler): string =
  result = "ThueShuffler[step=" & $s.step & " seed=" & $s.seed & "]"
