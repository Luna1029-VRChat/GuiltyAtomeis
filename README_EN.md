# GuiltyAtomeis V11 — Open Source Edition

**GuiltyAtomeis (OSS Edition)** is an experimental programming language system that compiles to encrypted bytecode running on a stack-based 4D maze virtual machine.  
It features an advanced security model focused on obfuscation, anti-debugging, anti-patching, and environment detection.

## V11 Security Enhancements (New Protections)

The latest V11 edition implements the full suite of security mechanisms specified by the Atomeis architecture:

- **Anti-Wrapper & Environment Detection (7 Categories)**
  - **Linux**: Active `ptrace` tracer checks, `/proc/self/status` TracerPid parsing (with smart process command-name verification to prevent false-positives under IDE/Language Server wrappers), `/proc/self/wchan` wait channel monitoring, `LD_PRELOAD` detection, and `/proc/self/maps` memory scans for debugger libraries (frida, ida, gdb, etc.).
  - **Windows / MinGW**: Direct PEB (Process Environment Block) checking, standard Win32 debugger API hooks (`IsDebuggerPresent`, `CheckRemoteDebuggerPresent`), and debugger thread hiding via `NtSetInformationThread`.
  - **Cross-Platform**: High-resolution execution timing checks to detect debugger single-stepping, and suspicious environmental variable scans.
- **Obfuscated Decoy Loop**
  - Triggered immediately upon detecting any debugger, sandbox, or binary patching attempt. Redirects execution to an infinite, CPU-heavy obfuscated calculation loop (`decoy_loop`), hanging the tracer or debugger.
- **Self-Integrity & FNV-1a Checksum Footer**
  - The compiler automatically signs compiled executables with an 8-byte FNV-1a checksum and a 4-byte `"ATMX"` trailer (12 bytes total) at the end of the file. The executable self-validates its integrity on startup. Any modifications trigger the decoy loop instantly.
- **String Pool Obfuscation (XOR Encoding)**
  - Prevents secret flags and strings from being exposed to simple static analysis tools like `strings`. The compiler encrypts the string pool (`poolData`) using XOR keys derived from the compile-time seed, and decrypts them on-the-fly in memory.

## Features

- **SOUL language** — Python-like indentation-based syntax, stack-based semantics
- **4D Maze VM** — Instruction pointer derived from 4D toroidal coordinates with Befunge-style walking execution model
- **AutonomousMalbolge Encryption** — All runtime values stored as FHE-like encrypted blocks
- **Thue-Morse ISA Shuffling** — Dynamic opcode permutation table updated every step
- **ORAM** — Oblivious RAM hiding all memory access patterns

## Components

| Component | Description |
|---|---|
| `atmc` | Compiler. Compiles `.atx` source into obfuscated and signed self-contained executables |
| `atomeis_runtime` | Runtime stub embedded in every compiled binary. Handles VM execution and anti-debugging |

## Building

### Prerequisites
- Nim 2.2.10+
- GCC / MinGW-w64 (for Windows cross-compilation)

### Linux
```bash
./build.sh
```

### Windows (Cross-Compilation Supported)
When compiling a target with a `.exe` extension on Linux, `atmc` automatically applies `-d:mingw --passL:-static` to compile a statically-linked standalone Windows binary.

## Usage

### Compile a source file
```bash
./atmc source.atx output
```

### Compile to a Windows target
```bash
./atmc source.atx output.exe
```

### Debug mode (security disabled)
```bash
./atmc source.atx output --debug
```

## Language Specification & Security Docs

For technical specifications and internal details:

- [SOUL.md](docs/SOUL.md) — Complete language specification
- [SYNTAX.md](docs/SYNTAX.md) — Syntax reference
- [STATUS.md](docs/STATUS.md) — Detailed security status & hashes
- [TESTING.md](docs/TESTING.md) — Compilation & testing guide

## License

MIT

## Author

宵猫ルナ (Yorunekoruna)
