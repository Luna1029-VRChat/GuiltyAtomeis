# GuiltyAtomeis V11 — セキュリティステータス

## 総合セキュリティレベル評価

| 指標 | 値 |
|---|---|
| **推定AI突破時間** | 120〜150分以上（V11でのアンチデバッグ・文字列プール隠蔽導入後） |
| **目標突破時間** | 120分以上（達成） |
| **実装セキュリティ機構数** | 31系統 |
| **自己完全性チェック呼び出し箇所** | 12箇所（ランタイムスタブ）+ 4箇所（VM内部）+ FNV-1a自己署名検証（起動時） |
| **最終テスト結果** | 7/7 合格、デバッガ/改ざん検知テスト 3/3 合格 |

---

## 署名フッター構造（最終12バイト）

V11より、コンパイル後のバイナリに末尾12バイトの完全性フッターが署名されます。

```
offset: -12   storedHash: uint64      # FNV-1a Checksum of file contents (0 to fileSize-12)
offset: -4    magic:      char[4]     # "ATMX" magic signature
```

起動時、バイナリは自身のファイルサイズから末尾12バイトを引いた範囲 of FNV-1a ハッシュ値を計算し、埋め込まれている `storedHash` および `magic` と照合します。不一致があった場合、即座に難読化デコイループが起動します。

---

## セキュリティ機構一覧（31系統）

### レイヤー0: フッター完全性 & 自己署名検証

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L0 | VERSION_TAG検証 | フッター終端の8バイトマジックを照合。不正な追記を検出 | `atomeis_runtime.nim`, `atmc.nim` |
| L27 | キャナリ検証 | フッター末尾4バイト `0x87654321` で完全性確認 | `atmc.nim` |
| L32 | FNV-1a & ATMX 整合性検証 | 起動時にファイルサイズ-12バイトまでのFNV-1aハッシュを計算し署名と照合 | `atmc_payload.nim`, `atmc.nim` |

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

### レイヤー3: 改ざん・デバッグ検出時の応答（Active defense）

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L4 | COME FROM デコイリダイレクト | 改ざん検出時に4D迷路座標をデコイ位置に上書き | `vm.nim` |
| L5 | 無限偽回復ループ | 「回復中… 99%完了」と見せかけて永遠に継続 | `vm.nim` |
| L6 | 暗号化命令バイト | 改ざん検出後の命令をノイズでXOR破壊 | `vm.nim` |
| L7 | buildEngine 状態破壊 | Thue ISA 進化履歴を破壊し全デコードを不可能化 | `vm.nim` |
| L34 | デコイループ (Decoy Loop) | 環境アノマリー検知・署名不一致時にCPU100%高負荷計算の無限ループへ強制移行 | `entropy_engine.hpp` |

### レイヤー4: AI解析耐性（ハルシネーション誘発）

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L8 | 双子デコイ関数 | 本物と酷似した偽の `selfCheckIntegrity_twin`（定数・比較論理が異なる） | `atomeis_runtime.nim` |
| L9 | proc変数間接呼び出し | `checker`/`decoy` 変数で関数を切り替え、静的コールグラフを無効化 | `atomeis_runtime.nim` |
| L10 | 偽装コメント・定数 | 「collectSystemMetrics」「markOperationComplete」などのミスリーディング命名 | `atomeis_runtime.nim` |
| L18 | 冗長ロジック | 論理的に同一 of 比較を二重記述（`a != b` と `not (a == b)`） | `atomeis_runtime.nim`, `vm.nim` |
| L24 | カナリア数値書式チェック | 0-9のint32/int64文字列化を繰り返し検証 | `atomeis_runtime.nim`, `vm.nim` |
| L25 | assertEq 三重チェック | 文字列比較を3通りの方法で検証 | `atomeis_runtime.nim`, `vm.nim` |

### レイヤー5: VM・コード難読化

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L11 | Thue ISA 命令シャッフル | 命令バイトをThue-Morse系列で動的シャッフル | `vm.nim`, `atmc.nim` |
| L12 | ORAM（メモリ oblivious化） | 特権メモリアクセスをORAM経由で難読化 | `vm.nim` |
| L13 | 4D迷路座標PCマッピング | プログラムカウンタを4次元座標から導出 | `vm.nim` |
| L14 | Sin（罪）軸ドリフト | 真性乱数による座標ドリフトで実行経路を攪乱 | `vm.nim` |
| L15 | ストリングプール難読化 | 文字列エントリをXOR暗号化 | `utils.nim` |
| L17 | 読取り後ノイズ挿入 | 分離バッファ読取り後に0xEEで上書き | `vm.nim` |
| L33 | 文字列プールXOR暗号化 | stringsによる静的抽出を防ぐため、プールデータ全体を起動シードでXOR難読化 | `atmc.nim`, `atmc_payload.nim` |

### レイヤー6: 動的環境・デバッガ検出 (V11追加)

| # | 機構 | 説明 | ソース |
|---|---|---|---|
| L28 | Linux ptrace 検知 | `ptrace(PTRACE_TRACEME)` が拒否された場合にデバッガを検出 | `entropy_engine.hpp` |
| L29 | TracerPid & comm検証 | `/proc/self/status` から `TracerPid` を抽出し、その親プロセスのコマンド名が gdb/strace 等か照合（IDEラッパー等の誤検知を排除） | `entropy_engine.hpp` |
| L30 | wchan 待機チャンネル検証 | `/proc/self/wchan` を読み取り、プロセスがデバッガにトレース停止中か判定 | `entropy_engine.hpp` |
| L31 | LD_PRELOAD 検知 | 環境変数 `LD_PRELOAD` によるライブラリインジェクションを検出 | `entropy_engine.hpp` |
| L35 | maps スキャン | `/proc/self/maps` をスキャンし、IDA/GDB/Frida/Jeb等のロード領域を検出 | `entropy_engine.hpp` |
| L36 | WindowsデバッガAPI検知 | `IsDebuggerPresent()`, `CheckRemoteDebuggerPresent()`, PEB監視, `NtSetInformationThread` によるスレッド隠蔽 | `entropy_engine.hpp` |
| L37 | タイミング検証 | 短いループの実行時間（us単位）を測定し、ステップ実行や仮想化オーバーヘッドを検出 | `entropy_engine.hpp` |
| L38 | 不審な環境変数チェック | `FRIDA_AUTHORITY` や `IDA_LICENSE` などの解析環境変数スキャン | `entropy_engine.hpp` |

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
| Obfuscation XOR key | `(buildSeed xor index) mod 256` | 文字列プールXOR復号化キー |

---

## テスト結果

### 機能テスト

| テスト | ソース | 結果 | 出力 |
|---|---|---|---|
| test_add | `test_add.atx` | ✅ 通過 | `300` |
| test_func | `test_func.atx` | ✅ 通過 | `10\n20` |
| test_judge | `test_judge.atx` | ✅ 通過 | `yes` |
| test_orbit | `test_orbit.atx` | ✅ 通過 | `0\n1\n2\n3\n4` |
| test_simple | `test_simple.atx` | ✅ 通過 | `hello from atomeis\n42\n999` |
| test_stigma | `test_stigma.atx` | ✅ 通過 | `two` |
| test_while | `test_while.atx` | ✅ 通過 | `1\n2\n3\n4` |

### 耐解析テスト

| 検証項目 | 方法 | 期待される挙動 | 結果 |
|---|---|---|---|
| **改ざん検知 (Anti-Patching)** | 署名済みバイナリの1バイトを書き換え | 起動時にFNV-1aフッターと不一致になり、即座に `decoy_loop`（CPU100%）に遷移 | ✅ 合格 |
| **GDB接続検知 (Anti-GDB)** | `gdb -batch -ex "run" ...` で実行 | ptrace及びTracerPidによりGDBを検出し、即座にハングアップ | ✅ 合格 |
| **Strace接続検知 (Anti-Strace)** | `strace ...` で実行 | 親プロセスのTracerPidおよび `comm` (strace) 検知によりハングアップ | ✅ 合格 |

---

## ビルド環境

| 項目 | 値 |
|---|---|
| コンパイラ | Nim 2.2.10 |
| モード | release（opt: speed, mm: orc） |
| ターゲット | Linux x86-64 / Windows x86-64 (MinGW) |
