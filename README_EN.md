# GuiltyAtomeis V10 — Open Source Edition

**GuiltyAtomeis (OSS Edition)** is an experimental programming language system that compiles to encrypted bytecode running on a stack-based 4D maze virtual machine.  
It features a lightweight security model focused on obfuscation. A full-security (Closed Source) edition is available separately.

## Features

- **SOUL language** — Python-like indentation-based syntax, stack-based semantics
- **4D Maze VM** — Instruction pointer derived from 4D toroidal coordinates with Befunge-style walking execution model
- **AutonomousMalbolge Encryption** — All runtime values stored as FHE-like encrypted blocks
- **Thue-Morse ISA Shuffling** — Dynamic opcode permutation table updated every step
- **ORAM** — Oblivious RAM hiding all memory access patterns

## Components

| Component | Description |
|---|---|
| `atmc` | Compiler. Compiles `.atx` source into obfuscated self-extracting executables |
| `atomeis_runtime` | Runtime stub embedded in every compiled binary. Handles VM execution |

## Building

### Prerequisites
- Nim 2.2.10+

### Linux
```bash
./build.sh
```

### Windows
```cmd
build.bat
```

After building, the following binaries are produced:
- `atmc` — The compiler
- `atomeis_runtime` — The runtime stub

## Usage

### Compile a source file
```bash
./atmc source.atx output
```

### Debug mode (security disabled)
```bash
./atmc source.atx output --debug
```

## Language Specification

For full language details, see:

- [SOUL.md](docs/SOUL.md) — Complete language specification
- [SYNTAX.md](docs/SYNTAX.md) — Syntax reference
- [STATUS.md](docs/STATUS.md) — Security mechanisms overview
- [TESTING.md](docs/TESTING.md) — Testing guide

## Example

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

## License

MIT

## Author

宵猫ルナ (Yorunekoruna)
