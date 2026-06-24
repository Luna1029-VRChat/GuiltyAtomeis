# GuiltyAtomeis V11 — Open Source Edition

**GuiltyAtomeis** はスタックベースの4次元迷路VM上で動作する暗号化バイトコードにコンパイルする実験的なプログラミング言語処理系です。  
高度な難読化と耐解析（アンチデバッグ・改ざん検出・難読化）を中心とした軽量セキュリティモデルを採用しています。

## V11 での強化ポイント（新セキュリティ機能）

最新のV11では、Atomeisのセキュリティ仕様に基づき、以下の耐解析機能が新たに統合されました。

- **アンチラッパー & 環境検出（7系統）**
  - **Linux**: `ptrace` アタッチチェック、`TracerPid` 監視（IDE/Language Server 等のラッパーによる誤検知を防止するコマンド名検証ロジック付き）、`wchan` 待機チャンネル検証、`LD_PRELOAD` 検知、`/proc/self/maps` 内のデバッグライブラリ（frida, ida, gdb 等）スキャン。
  - **Windows / MinGW**: PEB（Process Environment Block）直接チェック、`IsDebuggerPresent` / `CheckRemoteDebuggerPresent`、デバッガからのスレッド秘匿（`NtSetInformationThread`）。
  - **クロスプラットフォーム**: 実行速度の異常差分を検知するタイミング検証、不審な環境変数チェック。
- **デコイループ（Decoy Loop）**
  - デバッガや改ざんが検出された瞬間にトリガーされ、CPU 100%を消費する複雑な無意味計算ループ（`decoy_loop`）へ処理を逃がし、解析ツールをハングアップさせます。
- **自己整合性検証 & FNV-1a フッター署名**
  - コンパイル後の実行ファイルの末尾に、8バイトの FNV-1a チェックサムと4バイトの `"ATMX"` マジックフッター（計12バイト）を自動で署名。起動時に自身のファイルを走査して整合性を検証し、1バイトでも書き換えられていれば即座にデコイループを起動します。
- **文字列プールの暗号化（XOR隠蔽）**
  - 秘密のフラグなどの文字列リテラルが `strings` コマンド等で平文のまま露出するのを防ぐため、コンパイル時に文字列プール（`poolData`）全体を暗号シードに基づくXORで難読化。実行時にのみメモリ上で復号してVMに供給します。

## 特徴

- **SOUL言語** — Pythonライクなインデント構文のスタックベース言語
- **4D迷路VM** — 命令ポインタを4次元トーラス座標から導出し、Befungeスタイルの歩行を行う難読化実行モデル
- **AutonomousMalbolge暗号** — 全実行時値をFHEライクな暗号化ブロックで保持
- **Thue-Morse ISAシャッフル** — 命令バイトを動的置換テーブルで毎ステップ書換
- **ORAM** — 全メモリアクセスパターンを秘匿するOblivious RAM

## コンポーネント

| コンポーネント | 説明 |
|---|---|
| `atmc` | コンパイラ。`.atx` ソースを難読化・暗号化済み自己実行形式バイナリにコンパイル |
| `atomeis_runtime` | 全コンパイル済みバイナリに埋め込まれるランタイムスタブ。VM実行および環境検知を担当 |

## ビルド方法

### 依存
- Nim 2.2.10+
- GCC / MinGW-w64 (Windowsクロスコンパイル用)

### Linux
```bash
./build.sh
```

### Windows (Mingwクロスコンパイル対応)
Linux上でWindows向け実行ファイル（`.exe`）をビルドする場合は、自動的に `-d:mingw --passL:-static` フラグが適用され、静的リンクされたスタンドアロンな Windows バイナリが生成されます。

## 使い方

### ソースのコンパイル
```bash
./atmc source.atx output
```

### Windows向けコンパイル
```bash
./atmc source.atx output.exe
```

### デバッグモード（セキュリティ無効）
```bash
./atmc source.atx output --debug
```

## 言語仕様・セキュリティ詳細

言語や各保護機能の技術詳細については、以下を参照してください。

- [SOUL.md](docs/SOUL.md) — 完全な言語仕様書
- [SYNTAX.md](docs/SYNTAX.md) — 構文リファレンス
- [STATUS.md](docs/STATUS.md) — セキュリティ機構・ハッシュ詳細
- [TESTING.md](docs/TESTING.md) — テスト・ビルドガイド

## ライセンス

MIT

## 作者

宵猫ルナ
