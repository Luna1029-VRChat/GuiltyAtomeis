# GuiltyAtomeis V10 — SOUL言語仕様書

## 0. 開発ワークフロー

全開発作業は `/tmp` 配下で行い、作業完了後に `/media/veracrypt1/GuiltyAtomeis` に同期すること。

```
cp -a /tmp/opencode/<作業ディレクトリ>/* /media/veracrypt1/GuiltyAtomeis/
```

理由: ストレージの耐久性を考慮し、一時領域で作業してから最終格納先に反映する。

## 1. 言語概要

| 項目 | 値 |
|---|---|
| 名称 | GuiltyAtomeis / Atomeis SOUL |
| バージョン | V10 |
| ソースファイル拡張子 | `.atx` |
| コンパイル済み実行ファイル | Linux: 拡張子なし / Windows: `.exe` |
| コンパイラ | `atmc`（Atomeis MaChine） |
| ランタイムスタブ | `atomeis_runtime`（全コンパイル済み実行ファイルに埋め込まれるスタブ） |
| パラダイム | スタックベース、インデント依存、Pythonライク構文。FHE風暗号化・ORAM・Thue-Morse ISAシャッフル・自律完全性防御を備えた4D迷路VM上で実行される暗号化/シャッフル済みバイトコードにコンパイル |

## 2. 構文

### 2.1 字句トークン

| トークン | 構文 | 説明 |
|---|---|---|
| 整数 | `0-9+` | `int32` リテラル |
| 文字列 | `"..."` | 文字列リテラル（プールインデックス化） |
| 識別子 | `[a-zA-Z_][a-zA-Z0-9_]*` | 変数/関数名 |
| `+` `-` `*` `/` | | 算術演算子 |
| `^` | | ビット単位XOR |
| `<<` `>>` | | ビットシフト |
| `==` `!=` `<` `>` `<=` `>=` | | 比較演算子 (int32) |
| `=` | | 代入 |
| `( )` `{ }` `,` `:` | | 区切り記号 |

**キーワード**: `reveal exit judge seal spiral rite void stigma fate abyss orbit import use_python raw jmp jz getarg open read close write`

**組み込み関数**: `confess input map_new map_set map_get license_sync copy_all check encrypt evolve history_hash init_engine compile list_append write_block`

### 2.2 文法

```
program     → statement*
statement   → simple_stmt | compound_stmt
simple_stmt → expr | ident "=" expr
compound_stmt →
    "reveal" expr
  | "exit" [expr]
  | "judge" expr ":" block ["seal" ":" block]
  | "spiral" expr ":" block
  | "rite" ident "(" [ident ("," ident)*] ")" ":" block
  | "void" ":" block
  | "stigma" expr ":" indent ("fate" [expr] ":" block)* ["abyss" ":" block] dedent
  | "orbit" ident "in" expr ":" block
  | "import" string
  | "use_python" "{" block "}"
  | "getarg" "(" [expr] ")"
  | "open"  "(" [expr] ")"
  | "read"  "(" [expr] ")"
  | "close" "(" [expr] ")"
  | "write" "(" expr "," expr ")"
  | "raw" expr
  | builtin_name "(" ... ")"
```

### 2.3 演算子優先順位（低→高）

```
expr   → cmp (("=="|"!="|"<"|">"|"<="|">=") cmp)?
cmp    → shift (("+"|"-"|"^") shift)*
shift  → term (("<<"|">>") term)*
term   → factor (("*"|"/") factor)*
factor → int | string | ident | "(" expr ")" | ident "(" ... ")"
```

### 2.4 インデント

Pythonスタイル: `tkIndent`/`tkDedent` トークン。タブ1つ = スペース4つ。`#` で行末コメント。

### 2.5 サンプルプログラム

**Hello World**:
```
reveal("Hello from secure binary")
reveal(12345)
exit(0)
```

**変数と演算**:
```
a = 100
b = 200
x = a + b
reveal(x)
```

**条件分岐**:
```
judge 1 < 2:
    reveal("yes")
seal:
    reveal("no")
exit(0)
```

**Spiral（while）ループ**:
```
x = 1
spiral x < 5:
    reveal(x)
    x = x + 1
exit(0)
```

**関数定義**:
```
rite foo(a, b):
    reveal(a)
    reveal(b)
foo(10, 20)
exit(0)
```

**Switch（stigma）**:
```
x = 2
stigma x:
    fate 1:
        reveal("one")
    fate 2:
        reveal("two")
    abyss:
        reveal("other")
exit(0)
```

**カウントループ（orbit）**:
```
orbit i in 5:
    reveal(i)
exit(0)
```

## 3. データ型

| 型 | 表現 | 説明 |
|---|---|---|
| int32 | 32-bit signed | 全実行時値。演算は32-bit |
| FheBlock | `{low: uint64, high: uint64}` | 暗号化値: `low = rk*1e9 + data + 10`, `high = entropy` |
| String | プールインデックス（タグ `0x40000000 + idx`） | コンパイル時にプール割当 |
| Map | `Table[uint64, FheBlock]` | ヒープ辞書 |
| List | 順次 `Table` エントリ | ヒープ動的配列 |
| FileHandle | int32 | 不透明ファイル記述子 |

## 4. 命令セット（OpCodes from `isa.nim`）

### スタック

| Opcode | 値 | 説明 |
|---|---|---|
| opPush | 0x01 | int32リテラルをプッシュ（次の4バイト） |
| opPushStr | 0x90 | 文字列プールタグをプッシュ |
| opInput | 0x91 | 入力フィードから1バイト読み取り |
| opDup | 0x12 | スタックトップを複製 |
| opPop | 0x13 | ポップして破棄 |

### 算術/ビット演算（bをポップ、aをポップ、結果をプッシュ）

| Opcode | 値 | 操作 |
|---|---|---|
| opAdd | 0x02 | `a + b` |
| opSub | 0x03 | `a - b` |
| opMul | 0x04 | `a * b` |
| opDiv | 0x05 | `a / b`（0除算→0） |
| opXor | 0x06 | `a xor b` |
| opAnd | 0x07 | `a and b` |
| opOr | 0x08 | `a or b` |
| opShl | 0x09 | `a << (b & 0x1F)` |
| opShr | 0x0A | `a >> (b & 0x1F)` |

### メモリ

| Opcode | 値 | 説明 |
|---|---|---|
| opStore | 0x10 | 値をポップ→アドレスに格納（次の4バイト） |
| opLoad | 0x11 | アドレスからロード→プッシュ |

### I/O

| Opcode | 値 | 説明 |
|---|---|---|
| opPrint | 0x20 | ポップ: タグ付きならプール文字列、それ以外は整数を出力 |
| opOpen | 0x50 | ファイルを読み取り用にオープン→fdをプッシュ |
| opClose | 0x51 | fdをクローズ |
| opRead | 0x52 | 文字を読み取り→文字/-1をプッシュ |
| opWrite | 0x53 | 文字をポップ、fdをポップ→書き込み |
| opCopyAll | 0x54 | dstFdをポップ、srcFdをポップ→コピー |
| opWriteBlock | 0x61 | fdをポップ、文字列をポップ→文字列全体を書き込み |

### 制御フロー

| Opcode | 値 | 説明 |
|---|---|---|
| opJmp | 0x40 | 4バイトターゲットにジャンプ |
| opJz | 0x41 | ポップ; ゼロならジャンプ |
| opCall | 0x42 | 4D座標を保存、リターンアドレスをプッシュ、ジャンプ |
| opRet | 0x43 | 4D座標を復元、リターンアドレスをポップ |
| opExit | 0xFF | 最終完全性チェック、終了 |

### 比較

| Opcode | 値 | プッシュ |
|---|---|---|
| opEq | 0x30 | `a == b` なら1、それ以外は0 |
| opNe | 0x31 | `a != b` なら1、それ以外は0 |
| opLt | 0x32 | `a < b` なら1、それ以外は0 |
| opGt | 0x33 | `a > b` なら1、それ以外は0 |
| opLe | 0x34 | `a <= b` なら1、それ以外は0 |
| opGe | 0x35 | `a >= b` なら1、それ以外は0 |

### 暗号/エンジン

| Opcode | 値 | 説明 |
|---|---|---|
| opEncrypt | 0x60 | スタックトップを再暗号化 |
| opEvolve | 0x62 | ポップ→`evolveIsa(byte)` |
| opHistoryHash | 0x63 | `getHistoryHash(pc)` をプッシュ |
| opInitEngine | 0x64 | シードをポップ→エンジン再初期化 |
| opCompile | 0x66 | 文字列タグをポップ（スタブ: 0をプッシュ） |

### データ構造

| Opcode | 値 | 説明 |
|---|---|---|
| opMapNew | 0x70 | サイズをポップ→新規マップ→mapIdをプッシュ |
| opMapSet | 0x71 | mapId, key, valをポップ→設定 |
| opMapGet | 0x72 | mapId, keyをポップ→値をプッシュ |
| opListAppend | 0x73 | listId, valをポップ→追加 |

### ライセンス/完全性

| Opcode | 値 | 説明 |
|---|---|---|
| opLicenseSync | 0x80 | `stigma = 0xDEADBEEFCAFEBABE` を設定 |
| opCheck | 0xFB | 二重ハッシュを再計算; 不一致→`integrityFailed = true`, COME FROMリダイレクト |
| opNoise | 0xEE | 消費済みバイトを上書き（難読化） |

### V10拡張

| Opcode | 値 | 説明 |
|---|---|---|
| opLoadAtb | 0xA0 | idxをポップ→ATBモジュール内容をプッシュ |
| opSwitchParser | 0xA1 | モードをポップ→Pythonパーサーを切替 |
| opRawExec | 0xA2 | valをポップ: `0xDD`なら文字出力; 特権ならシェルコマンド実行 |
| opAbsolution | 0xB0 | `sin=0`, `w=0` をリセット; エントロピースパイラルをリセット |
| opGetArg | 0x65 | idxをポップ→CLI引数文字列をプッシュ |

## 5. 実行モデル — 4D迷路

### 5.1 状態

| 変数 | 意味 | 範囲 |
|---|---|---|
| `x y z w` | 4D座標 | 0..1023（トーラス） |
| `dx dy dz dw` | 方向ベクトル | -1, 0, または 1 |
| `sin` | Sin（罪）軸ドリフト | float64 |

### 5.2 PC導出（セキュアモード）

```
pc = (x + y*1024 + z*1024^2 + w*1024^3) mod originalLen
```

### 5.3 Befunge歩行

各命令後:
```
x = (x + dx) mod 1024
y = (y + dy) mod 1024
z = (z + dz) mod 1024
```

デフォルト: `dx=1`, `dy=0`, `dz=0`, `dw=0`（+X方向移動）

### 5.4 Sin（罪）ドリフト

```
sin += random_float(0..1)        # generateTrueSpice() より
w = (w + int(sin)) mod 1024      # W軸ドリフト
opAbsolution → sin=0, w=0        # リセット
```

### 5.5 命令フェッチパイプライン

1. 4D座標からPCを計算（デバッグモードでは順次）
2. `pc / 16` → パケットインデックス
3. `fetchPacket()` → 復号 + Thueデコード 16バイトパケット
4. `pc mod 16` 位置のバイトを読み取り
5. 消費済みバイトを分離バッファ内で `opNoise` (0xEE) で上書き
6. Befunge歩行を適用

### 5.6 COME FROM（完全性違反応答）

ハッシュ不一致検出時:
- `integrityFailed = true` を設定
- `corruptHistory()` → エンジン register_a = 0
- デコイPCを計算: `(seed xor hash1 xor stepCount) mod originalLen`
- 4D座標をデコイPCに設定
- 無限偽回復ループに突入:
  - 段階的に "SIN recalibration: NN% complete" を表示
  - "Self-healing: NN sectors processed"
  - "Convergence at 9N% - almost there!"
  - 実際には回復しない
- 以降の全命令バイトを `x xor y xor z xor w` でXOR

## 6. メモリモデル

### 6.1 スタック
- `seq[FheBlock]` — 全値が暗号化
- 算術演算: 復号→計算→再暗号化（位置依存）

### 6.2 ORAM（セキュアモード）
- Oblivious RAM: 全アクセスパターンを秘匿
- `buckets: seq[OramBlock]` — 物理ストレージ
- `posMap: Table[uint64, int]` — 秘密位置マッピング
- `stash: Table[uint64, FheBlock]` — ライトバックキャッシュ
- 毎アクセスで全バケットスキャン

### 6.3 デバッグデータ（非セキュア）
単純な `seq[int32]` 配列。直接アクセス。

### 6.4 ヒープ（マップ/リスト）
- `heap: Table[uint64, Table[uint64, FheBlock]]`
- マップID: `(cast[uint64](addr vm) xor size) & 0x7FFFFFFF`
- 全値が暗号化

### 6.5 Stigma
`stigma: uint64` — `opLicenseSync` により `0xDEADBEEFCAFEBABE` に設定

## 7. 暗号化 — AutonomousMalbolge暗号

### 7.1 エンジン状態
- `register_a: uint64` — 一次状態
- `weights[4]: uint64` — registerから派生
- `engine_checksum: uint64` — コンパイル時完全性ハッシュ

### 7.2 鍵導出
```
weights[0] = val xor 0x5555555555555555
weights[1] = (val << 32) | (val >> 32)
weights[2] = val xor 0xAAAAAAAAAAAAAAAA
weights[3] = ~val
```

### 7.3 churn() — 状態発展
```
register_a ^= spice ^ engine_checksum ^ accumulated_sin
register_a = ROTL13(register_a)
register_a *= 0xBF58476D1CE4E5B9
weights[register_a % 4] ^= register_a
```

### 7.4 stableEncrypt/Decrypt
```
r_key = (register_a ^ index ^ engine_checksum) % 100000000
out_low = r_key * 1000000000 + (uint32)data + 10
out_high = RDRAND()    # 暗号化毎に新しいエントロピー
```

## 8. Thue-Morse ISAシャッフル

### 8.1 概念
全命令バイトを、各ステップで発展する置換テーブルを通じて動的に再マッピング。エンコーダとデコーダは対称的なテーブルを維持。

### 8.2 テーブル
- `encTable[256]` — 論理→物理
- `decTable[256]` — 物理→論理
- 16個のThue書換規則 `a → b`（1バイト交換規則）

### 8.3 ステップ毎の変異
```
ruleIdx = (step xor seed) % len(rules)
swap(encTable, rules[ruleIdx].a, rules[ruleIdx].b)
rebuild decTable from encTable
```

### 8.4 seek()
特定のThueステップに高速送り/巻き戻し。パケット境界合わせのデコードに使用。

## 9. コンパイルパイプライン

```
.atx ソース
  → レクサー（トークン化）
  → パーサー（AST）
  → コード生成（バイトコード）
  → Thue ISAシャッフル + AutonomousMalbolge暗号化（セキュアモード）
  → バイナリ合成（スタブ + プール + PIT + マップ + バイトコード + フッター）
```

### 9.1 コンパイラモード

| モード | フラグ | 説明 |
|---|---|---|
| exe | （デフォルト） | 完全コンパイル + セキュリティ |
| debug | `--debug` | セキュリティ無効（seed=0, 恒等Thue） |
| atb | `--atb` | 生バイトコードのみ |

### 9.2 変数割当
0からの順次アドレス（`symTable: Table[string, int]`）

### 9.3 コード生成パターン

| ASTノード | 出力 |
|---|---|
| `nkInt(n)` | `opPush n (int32 LE)` |
| `nkString(s)` | `opPushStr poolIndex` |
| `nkIdent(name)` | `opLoad varAddress` |
| `nkPrint(expr)` | `gen(expr); opPrint` |
| `nkExit(expr)` | `gen(expr); opExit` |
| `nkSpiral(cond, body)` | `[start] gen(cond); opJz exit; gen(body); opAbsolution; opJmp start` |
| `nkRite(name, args, body)` | `opJmp skip; opStore ...; body; opRet` |
| `nkCall(name, args)` | `gen(args); opCall funcAddr` |
| `nkOrbit(var, count, body)` | `opLt`/`opJz`/`opAdd` によるループ |
| `nkStigma(expr, branches)` | `opDup`/`opEq`/`opJz` チェインによるswitch |
| `nkImport(path)` | 再帰的レクサー+パーサー+生成 |
| `nkUsePython(body)` | `opSwitchParser 1; body; opSwitchParser 0` |

## 10. バイナリ形式

### 10.1 レイアウト（ファイル終端から逆方向に読む）

```
[終端 - 12 バイト]
  versionTag: uint64 (0x4755494C54594154 = "GUILTYAT")
  trailer: uint32 (0x87654321)

[終端 - 108 バイト: 構造フッター]
  reserved1: int64    # 0 (reserved)
  reserved2: int64    # 0 (reserved)
  secFlag: uint32     # 0xDEADBEEF（セキュア）/ 0x00000000（デバッグ）
  seed: int64         # エントロピーシード
  dataSize: int64     # バイトコードサイズ
  mapSize: int64      # マップセクションサイズ
  pitSize: int64      # パケットインデックステーブルサイズ
  poolSize: int64     # 文字列プールテーブルサイズ
  rawLen: int32       # バイトコード長（バイト単位）
  hash1: uint32       # 一次整合性ハッシュ
  hash2: uint32       # 二重整合性ハッシュ（seed XOR 0xDEADC0DE）
  textOffset: int64   # ELF .text セクションオフセット
  textSize: int64     # ELF .text セクションサイズ
  textHash: uint32    # .text セクションハッシュ（XOR 0x7D7D7D7D）
  layer4Expected: uint32 # 動的L4期待値ハッシュ（XOR 0x5A5A5A5A）

[フッターの前: バイトコード]
  seq[FheBlock] — 暗号化+シャッフル（セキュア）/ 生（デバッグ）

[バイトコードの前: マップ]
  numMaps: int32
  各マップ: mapLen, エントリ（key:uint8, valLen:int8, val:string）

[マップの前: PIT]
  numPackets: int32
  packetOffsets: seq[int32]

[PITの前: 文字列プール]
  numStrings: int32
  各文字列: strLen, strData（オプションで難読化）

[先頭: atomeis_runtime ELF]
```

### 10.2 ランタイム起動シーケンス
1. `selfCheckIntegrity()` × 2（5層: ASCII不変、桁100、複数桁、ハッシュテストベクター、.text ハッシュ）
2. `fetch_internal_resource()` — フッター読み取り、セクション位置を特定
3. バイトコード、マップ、PIT、プールを解析
4. VM初期化、AutonomousMalbolgeエンジン、シードからregister設定
5. `vm.run(...)` — 暗号化バイトコードを4D迷路内で実行
6. VM後 `selfCheckIntegrity()`

## 11. 完全性 & 改ざん防止機構

### 11.1 自己完全性チェック層（atomeis_runtime）

| 層 | 機構 | 場所 |
|---|---|---|
| L0 | フッター VERSION_TAG + トレーラーキャナリ検証 | `atomeis_runtime.nim:35-36, 155-156` |
| L1 | 数字文字列フォーマット不変条件（int32: 上位ニブル=3, 下位=数字） | `atomeis_runtime.nim:250-261` |
| L2 | 文字列連結 + 複数桁フォーマット検証 | `atomeis_runtime.nim:262-273` |
| L3 | `computeIntegrityHash` によるテストベクター（0x1111..., 0x2222... 等） | `atomeis_runtime.nim:274-280` |
| L4 | `.text` セクションハッシュ検証（`/proc/self/exe` 再読込、SHA256類似） | `atomeis_runtime.nim:144-180`, `vm.nim:238-251` |
| L5 | 動的テストベクター: シードを `.text` ハッシュから派生（`textHash xor 0x12345678`） | `atomeis_runtime.nim:274`, `atmc.nim:288-296` |

### 11.2 VM実行時チェック

| 検査 | 頻度 | 機構 |
|---|---|---|
| 二重整合性ハッシュ | 毎命令 | 2種シードで `computeIntegrityHash` |
| 数字文字列カナリア | 256命令毎 | int32/int64 フォーマット検証 |
| `.text` 再検証 | 1024命令毎 | `/proc/self/exe` 再読込 + 再ハッシュ |
| opCheck | オンデマンドVM命令 | 完全二重ハッシュ再計算 |
| opExit | プログラム終了時 | 完全二重ハッシュ再計算 |

### 11.3 完全性違反応答

完全性チェックが失敗した場合:
1. `buildEngine.corruptHistory()` — Thue ISA状態を破壊
2. 4D座標をデコイPCに上書き
3. 無限偽回復ループ（"SIN recalibration NN%", "Convergence at 9N%"）
4. 以降の全命令バイトを座標ノイズでXOR

### 11.4 AIハルシネーション対策

| 手法 | 実装 |
|---|---|
| 双子デコイ関数 | `selfCheckIntegrity_twin` は本物と同一だが定数 + 比較論理が異なる |
| Proc変数間接呼び出し | `checker`/`decoy` 変数がどの関数を実行するか型消去 |
| 誤解を招く命名 | `markOperationComplete`（成功を示唆する名前だが実際は無限ループ + quit） |
| 偽の定数 | `INTEGRITY_CHECK_DISABLED=false`, `SYSTEM_HEALTH_POLL=0.95`（冗長ノイズ） |
| ミスリーディングコメント | "collectSystemMetrics: gathers runtime telemetry"（実際は完全性検査） |
| 冗長アサーション | `a != b` + `not (a == b)` + `cmp(a,b) != 0` — 3つの同一パス |

### 11.5 改ざん耐性検証

バイナリ改ざん耐性は実証済み（第三者解析レポートより）:
- 旧版（単純ELF、V9同等）: ASCIIテーブル2バイト書き換えで出力改ざん可能
- 現行版（V10、全機構有効）: いかなる単純パッチでも出力変更不可能

## 12. 定数

```
VERSION_TAG       = 0x4755494C54594154   ("GUILTYAT")
TRAILER           = 0x87654321
STRING_TAG        = 0x40000000
SEC_FLAG_SECURE   = 0xDEADBEEF
SEC_FLAG_DEBUG    = 0x00000000
INTEGRITY_XOR     = 0xDEADC0DE
ORAM_KEY_XOR      = 0x0B1B10C0
FOOTER_SIZE       = 108
PACKET_SIZE       = 16
MAZE_DIM          = 1024
HASH_CONST_1      = 0x9e3779b97f4a7c15
HASH_CONST_2      = 0xbf58476d1ce4e5b9
HASH_CHECK_SEED   = 0x12345678
TEXT_HASH_XOR     = 0x7D7D7D7D
L4_XOR_KEY        = 0x5A5A5A5A
DUAL_HASH_XOR     = 0xDEADC0DE
```

## 13. Pythonトランスパイラ

セルフホスト型 `.py` → Atomeis トランスパイラ（`python_trans.atx`）。`print("...")` パターンを検出し、同等の Atomeis バイトコードをキャプチャバッファ経由で出力。生バイトは `raw(c)` で出力。`raw(221)` はデバッグ文字出力。
