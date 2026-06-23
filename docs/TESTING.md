# GuiltyAtomeis V11 — テスト・ビルドガイド

## 1. コンパイラのビルド

```bash
# デバッグモード（開発用、セキュリティ無効）
nim cpp --path:src src/atmc.nim

# リリースモード
nim cpp -d:release --app:console --path:src src/atmc.nim
```

### ランタイムスタブのビルド

```bash
# デバッグ（開発用）
nim cpp --path:src src/atomeis_runtime.nim

# リリース
nim cpp -d:release --app:console --path:src src/atomeis_runtime.nim
```

### 一括ビルド

```bash
# Linux
./build.sh

# Windows
build.bat
```

---

## 2. コンパイルと実行

```bash
# デバッグモード（セキュリティ無効）
atmc --debug source.atx output
chmod +x output
./output

# リリースモード（暗号化＋完全性保護＋アンチデバッグ＋文字列プール隠蔽有効）
atmc source.atx output
chmod +x output
./output

# ATB中間コード出力
atmc --atb source.atx output.atb
```

### Windows (Mingw) クロスコンパイル
Linux上でWindows向けにコンパイルする場合：
```bash
atmc source.atx output.exe
```
※自動的にMingwでクロスコンパイルされ、静的リンクされたスタンドアロンな Windows バイナリ（XOR文字列プールおよび環境検知保護付き）が生成されます。

---

## 3. ATX言語リファレンス（テスト実例）

### Hello World

```python
reveal("hello from atomeis")
reveal(42)
reveal(999)
exit(0)
```

コンパイル・実行:
```bash
atmc test_simple.atx output
./output
# → hello from atomeis
# → 42
# → 999
```

### 変数と算術

```python
a = 100
b = 200
reveal(a + b)
exit(0)
```

```bash
atmc test_add.atx output
./output
# → 300
```

### 条件分岐（judge）

```python
judge 1 < 2:
    reveal("yes")
seal:
    reveal("no")
exit(0)
```

```bash
atmc test_judge.atx output
./output
# → yes
```

### ループ（spiral）

```python
x = 1
spiral x < 5:
    reveal(x)
    x = x + 1
exit(0)
```

```bash
atmc test_while.atx output
./output
# → 1 2 3 4
```

### カウントループ（orbit）

```python
orbit i in 5:
    reveal(i)
exit(0)
```

```bash
atmc test_orbit.atx output
./output
# → 0 1 2 3 4
```

### 関数定義（rite）

```python
rite add(a, b):
    reveal(a + b)
add(10, 20)
exit(0)
```

```bash
atmc test_func.atx output
./output
# → 10
# → 20
```

### Switch文（stigma）

```python
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

```bash
atmc test_stigma.atx output
./output
# → two
```

### license_sync（VMライセンス状態設定）

```python
license_sync()
exit(0)
```

**注**: `license_sync()` はVM内のstigmaレジスタを設定する組み込み関数です。

---

## 4. Pythonトランスパイル

`.py` ファイルを `atmc` に渡すと、`python_trans.atb` モジュールを使用してトランスパイルします。

```bash
atmc script.py output
```

---

## 5. テスト一覧

| テストファイル | 検証内容 | 期待出力 |
|---|---|---|
| `test_simple.atx` | reveal / exit | `hello from atomeis` / `42` / `999` |
| `test_func.atx` | 関数定義と呼び出し | `10` / `20` |
| `test_while.atx` | spiralループ | `1` / `2` / `3` / `4` |
| `test_judge.atx` | judge条件分岐 | `yes` |
| `test_orbit.atx` | orbit forループ | `0` / `1` / `2` / `3` / `4` |
| `test_stigma.atx` | stigma match文 | `two` |

---

## 6. セキュリティ保護検証テスト（V11追加）

リリースビルドされた実行ファイルに対して以下のコマンドを実行し、保護機構が正常に動作するか確認します。

### GDBアタッチのテスト
```bash
gdb -batch -ex "run" ./output
# 期待動作: gdbを検知し、ハングアップ（CPU 100%の無限ループ）します。
```

### Straceのテスト
```bash
strace ./output
# 期待動作: straceを検知し、ハングアップ（CPU 100%の無限ループ）します。
```

### 静的バイナリ改ざん（アンチパッチ）のテスト
```bash
# Pythonスクリプト等でバイナリの任意の1バイトを書き換え
python3 -c "
data = bytearray(open('output', 'rb').read())
data[100] ^= 0x42
open('output_corrupted', 'wb').write(data)
" && chmod +x output_corrupted

# 実行
./output_corrupted
# 期待動作: 署名フッター（FNV-1aチェックサム）の検証に失敗し、即座にハングアップします。
```

### strings抽出テスト
```bash
strings ./output | grep -E "(FLAG|CORRECT|WRONG)"
# 期待動作: 文字列プールがXOR暗号化されているため、フラグ文字列や機密メッセージが露出しないことを確認します。
```

---

## 7. デバッグモードとリリースモードの違い

| 項目 | `--debug`（開発） | 通常（リリース） |
|------|-----------------|----------------|
| バイトコード暗号化 | 平文 | FHE暗号化 |
| Thue ISAシャッフル | なし | あり |
| ORAM | なし | あり |
| 文字列プール難読化 | なし（平文露出） | **あり（XOR暗号化）** |
| 自己署名 & 整合性検証 | なし | **あり（FNV-1a & Magic）** |
| 動的環境・デバッガ検出 | なし | **あり（7系統 + timing ほか）** |
| 検出時挙動 | なし | **あり（CPU100%デコイループ）** |
| コンパイル速度 | 速い | やや遅い |
