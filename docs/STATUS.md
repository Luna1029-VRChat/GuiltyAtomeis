# GuiltyAtomeis V10 — セキュリティステータス

## 総合セキュリティレベル評価

| 指標 | 値 |
|---|---|
| **推定AI突破時間** | 70〜100分（現状） |
| **目標突破時間** | 120分以上 |
| **実装セキュリティ機構数** | 24系統 |
| **自己完全性チェック呼び出し箇所** | 12箇所（atomeis_runtime）+ 4箇所（VM内部） |
| **最終テスト結果** | 7/7 合格 |

---

## フッター構造（最終108バイト）

```
offset: -108  licLen:   int64       # 0 (reserved)
offset: -100  reserved: int64       # 0 (reserved)
offset: -92   secFlag:  uint32      # 0xDEADBEEF / 0x00000000
offset: -88   seed:     int64       # Entropy seed
offset: -80   dataSize: int64       # Bytecode size
offset: -72   mapSize:  int64       # Map section size
offset: -64   pitSize:  int64       # PIT size
offset: -56   poolSize: int64       # String pool size
offset: -48   rawLen:   int32       # Original bytecode length
offset: -44   hash1:    uint32      # Primary integrity hash
offset: -40   hash2:    uint32      # Dual integrity hash
offset: -36   textOff:  int64       # .text section offset
offset: -28   textSize: int64       # .text section size
offset: -20   textHash: uint32      # .text hash (XOR 0x7D7D7D7D)
offset: -16   l4Hash:   uint32      # Layer 4 expected hash (XOR 0x5A5A5A5A)
offset: -12   VERSION_TAG (8 bytes)
offset: -4    TRAILER (4 bytes)
```

---

## セキュリティ機構一覧（24系統）

### レイヤー0: フッター完全性（基本検証）

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L0 | VERSION_TAG検証 | フッター終端の8バイトマジックを照合。不正な追記を検出 | `atomeis_runtime.nim`, `atmc.nim` |
| L27 | キャナリ検証 | フッター末尾4バイト `0x87654321` で完全性確認 | `atmc.nim` |

### レイヤー1: 静的バイナリ改ざん検出

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L1 | .text セクションハッシュ検証 | `/proc/self/exe` を再読込し .text を再ハッシュ、フッターの値と比較 | `utils.nim`, `atomeis_runtime.nim`, `vm.nim` |
| L26 | 動的テストベクター | Layer 4 のシードを .text ハッシュから派生（`textHash xor 0x12345678`） | `atmc.nim`, `atomeis_runtime.nim` |

### レイヤー2: ペイロード整合性

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L3 | ペイロード二重整合性ハッシュ | コード＋PIT＋マップ＋プールに対し2種類のシードで二重検証 | `vm.nim` |
| L21 | 毎命令デュアルハッシュチェック | 全命令実行時に二重ハッシュ照合 | `vm.nim` |
| L22 | opCheck 命令 | 任意タイミングで呼び出せるオンデマンド完全性検査VM命令 | `vm.nim` |
| L23 | opExit 命令 | プログラム終了時に自動実行される完全性検査 | `vm.nim` |

### レイヤー3: 改ざん検出時の応答

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L4 | COME FROM デコイリダイレクト | 改ざん検出時に4D迷路座標をデコイ位置に上書き | `vm.nim` |
| L5 | 無限偽回復ループ | 「回復中… 99%完了」と見せかけて永遠に継続 | `vm.nim` |
| L6 | 暗号化命令バイト | 改ざん検出後の命令をノイズでXOR破壊 | `vm.nim` |
| L7 | buildEngine 状態破壊 | Thue ISA 進化履歴を破壊し全デコードを不可能化 | `vm.nim` |

### レイヤー4: AI解析耐性（ハルシネーション誘発）

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L8 | 双子デコイ関数 | 本物と酷似した偽の `selfCheckIntegrity_twin`（定数・比較論理が異なる） | `atomeis_runtime.nim` |
| L9 | proc変数間接呼び出し | `checker`/`decoy` 変数で関数を切り替え、静的コールグラフを無効化 | `atomeis_runtime.nim` |
| L10 | 偽装コメント・定数 | 「collectSystemMetrics」「markOperationComplete」などのミスリーディング命名 | `atomeis_runtime.nim` |
| L18 | 冗長ロジック | 論理的に同一の比較を二重記述（`a != b` と `not (a == b)`） | `atomeis_runtime.nim`, `vm.nim` |
| L24 | カナリア数値書式チェック | 0-9のint32/int64文字列化を繰り返し検証 | `atomeis_runtime.nim`, `vm.nim` |
| L25 | assertEq 三重チェック | 文字列比較を3通りの方法で検証 | `atomeis_runtime.nim`, `vm.nim` |

### レイヤー5: VM難読化

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L11 | Thue ISA 命令シャッフル | 命令バイトをThue-Morse系列で動的シャッフル | `vm.nim`, `atmc.nim` |
| L12 | ORAM（メモリ oblivious化） | 特権メモリアクセスをORAM経由で難読化 | `vm.nim` |
| L13 | 4D迷路座標PCマッピング | プログラムカウンタを4次元座標から導出 | `vm.nim` |
| L14 | Sin（罪）軸ドリフト | 真性乱数による座標ドリフトで実行経路を攪乱 | `vm.nim` |
| L15 | ストリングプール難読化 | 文字列エントリをXOR暗号化 | `utils.nim` |
| L17 | 読取り後ノイズ挿入 | 分離バッファ読取り後に0xEEで上書き | `vm.nim` |

---

## 自己完全性チェック呼び出しマップ

### atomeis_runtime.nim `execute_internal()` 内（12回）

```
checker() ──┐  (after anti-wrapper)
decoy()  ───┤
            │
checker() ──┤  (after init_runtime_env)
decoy()  ───┤
            │
checker() ──┤  (before VM init)
decoy()  ───┤
            │
checker() ──┤  (after setRegister)
decoy()  ───┤
            │
checker() ──┤  (after vm.run)
decoy()  ───┤
            │
checker() ──┤  (exception path)
decoy()  ───┤  (exception path)
```

### vm.nim VMループ内

| 頻度 | チェック内容 |
|---|---|
| 毎命令 | デュアル整合性ハッシュ照合 |
| 256命令毎 | 数字書式検証カナリア |
| 1024命令毎 | .text 再ハッシュ検証（ディスクI/O） |
| オンデマンド | opCheck 実行時 |
| 終了時 | opExit 実行時 |

---

## XORキー一覧

| キー | 値 | 用途 |
|---|---|---|
| XOR_KEY | 0x7D7D7D7D | .text ハッシュ復号（フッター→生値） |
| L4_XOR_KEY | 0x5A5A5A5A | Layer 4 期待値復号 |
| Layer4 seed | 0x12345678 | .text ハッシュとXORしてLayer 4シード生成 |
| Dual hash | 0xDEADC0DE | 二重目ハッシュのシード用XOR |
| ORAM key | 0x0B1B10C0 | ORAM初期化シード用XOR |
| Thue addend | 0x9E3779B9 | Thue ISA シード加算値 |
| computeTextHash | 0x9E3779B97F4A7C15 | .text ハッシュ初期状態＋乗算定数 |
| computeIntegrityHash | 0x9e3779b97f4a7c15 | ペイロードハッシュ乗算定数 |

---

## テスト結果

| テスト | ソース | 結果 | 出力 |
|---|---|---|---|
| test_add | `test_add.atx` | ✅ 通過 | `300` |
| test_func | `test_func.atx` | ✅ 通過 | `10\n20` |
| test_judge | `test_judge.atx` | ✅ 通過 | `yes` |
| test_orbit | `test_orbit.atx` | ✅ 通過 | `0\n1\n2\n3\n4` |
| test_simple | `test_simple.atx` | ✅ 通過 | `hello from atomeis\n42\n999` |
| test_stigma | `test_stigma.atx` | ✅ 通過 | `two` |
| test_while | `test_while.atx` | ✅ 通過 | `1\n2\n3\n4` |

---

## 現在の課題

1. **AI突破推定値**: 70〜100分。残り20分の目標達成にはさらなるハルシネーション戦略が必要
2. **双子デコイがデッドコード**: 現状 `decoy` 変数は本物の関数を呼ぶため、双子はAIの解析時間消費にしか寄与しない。proc変数条件を実行時決定にできればより効果的
3. **ハッシュ定数の重複**: `0x9e3779b97f4a7c15` が `.text` ハッシュと `computeIntegrityHash` の両方に出現。統一された解析対象となるリスク

---

## ビルド環境

| 項目 | 値 |
|---|---|
| コンパイラ | Nim 2.2.10 |
| モード | release（opt: speed, mm: orc） |
| ターゲット | Linux x86-64 / Windows x86-64 |
