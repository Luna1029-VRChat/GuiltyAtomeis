# GuiltyAtomeis V10 — 構文 & 機能一覧

## 概要

SOUL（Secure Obfuscated Unified Language）は Python ライクなインデント構文を持ち、コンパイル後に完全に暗号化・シャッフルされたバイトコードとして4D迷路VM上で実行される言語です。全7テスト合格済み。

## 基本構文

### 変数と演算

数値は 32-bit signed 整数。演算子: `+` `-` `*` `/` `^` `<<` `>>`

```
a = 100
b = 200
x = a + b
reveal(x)     # → 300
```

### 文字列出力

```
reveal("Hello from secure binary")
reveal(12345)
```

### 条件分岐（judge / seal）

```
judge 1 < 2:
    reveal("yes")
seal:
    reveal("no")
```

比較演算子: `==` `!=` `<` `>` `<=` `>=`

### ループ（spiral）

```
x = 1
spiral x < 5:
    reveal(x)
    x = x + 1
# → 1 2 3 4
```

### カウントループ（orbit）

```
orbit i in 5:
    reveal(i)
# → 0 1 2 3 4
```

### 関数定義（rite）

```
rite foo(a, b):
    reveal(a)
    reveal(b)
foo(10, 20)
# → 10 20
```

### Switch（stigma / fate / abyss）

```
x = 2
stigma x:
    fate 1:
        reveal("one")
    fate 2:
        reveal("two")
    abyss:
        reveal("other")
# → two
```

### 早期脱出（void）

```
spiral true:
    reveal("once")
    void
# → once
```

## 実装済み機能

### 基本
- 変数宣言・代入
- 四則演算・ビット演算
- 文字列リテラル（プール管理）
- 文字列出力
- 整数出力

### 制御フロー
- `judge` / `seal` — if/else
- `spiral` — while ループ
- `orbit` — for カウントループ
- `void` — ループ脱出
- `stigma` / `fate` / `abyss` — switch/case/default
- `rite` / call — 関数定義・呼び出し
- `exit` — 終了

### I/O
- `open` / `close` — ファイルオープン・クローズ
- `read` — ファイル読み取り
- `write` — ファイル書き込み
- `copy_all` — ファイルコピー
- `write_block` — 文字列出力

### データ構造
- `map_new` / `map_set` / `map_get` — ハッシュマップ
- `list_append` — 動的配列

### 特殊
- `import` — ソースファイルインクルード
- `use_python` — Pythonパーサーモード切替
- `raw` — 生バイト出力（デバッグ）
- `getarg` — CLI引数取得
- `confess` — デバッグ出力
- `encrypt` / `evolve` / `history_hash` / `init_engine` / `compile` — VMエンジン制御
- `check` — 完全性チェック強制実行
- `license_sync` — ライセンス状態設定

## テスト一覧

```
test_add        a=100 b=200 x=a+b → 300
test_func       関数定義と呼び出し → 10, 20
test_judge      条件分岐 → "yes"
test_orbit      カウントループ → 0 1 2 3 4
test_simple     Hello World → "hello from atomeis" 42 999
test_stigma     switch文 → "two"
test_while      whileループ → 1 2 3 4
```

## コンパイル方法

```
# 通常ビルド（全セキュリティ有効）
atmc source.atx output.exe

# デバッグモード（セキュリティ無効）
atmc --debug source.atx output.exe

# 生バイトコード出力
atmc --atb source.atx output.atb
```

## 制限事項

- 64-bit 整数演算なし（int32のみ）
- 浮動小数点なし
- 文字列結合はコンパイル時のみ（`"a" & "b"` → プール解決）
- ネストされた関数定義なし
- 配列インデックスなし（マップ・リストで代替）
