# GuiltyAtomeis V10 — Open Source Edition

**GuiltyAtomeis（OSS Edition）** はスタックベースの4次元迷路VM上で動作する暗号化バイトコードにコンパイルする実験的なプログラミング言語処理系です。  
難読化を中心とした軽量セキュリティモデルを採用しています。フルセキュリティ版（Closed Source）は別リポジトリで配布されています。

## 特徴

- **SOUL言語** — Pythonライクなインデント構文のスタックベース言語
- **4D迷路VM** — 命令ポインタを4次元トーラス座標から導出し、Befungeスタイルの歩行を行う難読化実行モデル
- **AutonomousMalbolge暗号** — 全実行時値をFHEライクな暗号化ブロックで保持
- **Thue-Morse ISAシャッフル** — 命令バイトを動的置換テーブルで毎ステップ書換
- **ORAM** — 全メモリアクセスパターンを秘匿するOblivious RAM

## コンポーネント

| コンポーネント | 説明 |
|---|---|
| `atmc` | コンパイラ。`.atx` ソースを難読化済み自己実行形式バイナリにコンパイル |
| `atomeis_runtime` | 全コンパイル済みバイナリに埋め込まれるランタイムスタブ。VM実行を担当 |

## ビルド方法

### 依存
- Nim 2.2.10+

### Linux
```bash
./build.sh
```

### Windows
```cmd
build.bat
```

ビルドが完了すると以下が生成されます:
- `atmc` — コンパイラ
- `atomeis_runtime` — ランタイムスタブ

## 使い方

### ソースのコンパイル
```bash
./atmc source.atx output
```

### デバッグモード（セキュリティ無効）
```bash
./atmc source.atx output --debug
```

## 言語仕様

言語の詳細については以下を参照:

- [SOUL.md](docs/SOUL.md) — 完全な言語仕様書
- [SYNTAX.md](docs/SYNTAX.md) — 構文リファレンス
- [STATUS.md](docs/STATUS.md) — セキュリティ機構一覧
- [TESTING.md](docs/TESTING.md) — テストガイド

## サンプル

```
reveal("Hello from secure binary")
reveal(12345)
exit(0)
```

```
a = 100
b = 200
x = a + b
reveal(x)
```

## ライセンス

MIT

## 作者

宵猫ルナ
