import os, streams
import common/[isa, constants, utils]
import compiler/entropy_engine
import runtime/vm

proc executeBytecode*(bytecode: seq[FheBlock], pool: seq[string],
                      buildSeed: int64, originalLen: int,
                      args: seq[string]) =
  try:
    var vmEngine = initVM(false)
    var buildEngine = constructAuto()
    buildEngine.setRegister(buildSeed)
    vmEngine.run(bytecode, buildEngine, buildSeed, originalLen, pool, args)
  except Exception as e:
    echo "[!] CRITICAL_EXCEPTION: ", e.msg

when isMainModule:
  echo "GuiltyAtomeis V11 Runtime"
  echo "This binary is a runtime module."
  echo "Use 'atmc' to compile and produce executables."
