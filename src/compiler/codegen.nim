import types, ../common/isa, tables, lexer, parser, strutils, sequtils

var symTable: Table[string, int]
var funcTable: Table[string, int]
var stringPool: seq[string]
var nextAddr = 0
var bytecode: seq[uint8]
var inVoidBlock = false
var structDefs: Table[string, tuple[fields: seq[tuple[name: string, fieldType: string]], size: int, offsets: seq[int]]]
var externFuncs: seq[tuple[name: string, argCount: int]]
var loopBreakStack: seq[int]
var loopContinueStack: seq[int]
var varTypeMapping: Table[string, string]

proc writeInt32(val: int) =
    let v = val.int32
    bytecode.add(uint8(v and 0xFF))
    bytecode.add(uint8((v shr 8) and 0xFF))
    bytecode.add(uint8((v shr 16) and 0xFF))
    bytecode.add(uint8((v shr 24) and 0xFF))

proc writeInt64(val: int64) =
    bytecode.add(uint8(val and 0xFF))
    bytecode.add(uint8((val shr 8) and 0xFF))
    bytecode.add(uint8((val shr 16) and 0xFF))
    bytecode.add(uint8((val shr 24) and 0xFF))
    bytecode.add(uint8((val shr 32) and 0xFF))
    bytecode.add(uint8((val shr 40) and 0xFF))
    bytecode.add(uint8((val shr 48) and 0xFF))
    bytecode.add(uint8((val shr 56) and 0xFF))

proc writeFloat(val: float32) =
    let bits = cast[uint32](val)
    bytecode.add(uint8(bits and 0xFF))
    bytecode.add(uint8((bits shr 8) and 0xFF))
    bytecode.add(uint8((bits shr 16) and 0xFF))
    bytecode.add(uint8((bits shr 24) and 0xFF))

proc patchInt32(pos: int, val: int) =
    if pos < 0 or pos + 3 >= bytecode.len:
        raise newException(IndexDefect, "Bytecode patch out of bounds")
    let v = val.int32
    bytecode[pos] = uint8(v and 0xFF)
    bytecode[pos+1] = uint8((v shr 8) and 0xFF)
    bytecode[pos+2] = uint8((v shr 16) and 0xFF)
    bytecode[pos+3] = uint8((v shr 24) and 0xFF)

proc typeSize(tname: string): int =
    if tname in structDefs:
        result = structDefs[tname].size
    elif tname.startsWith("ptr ") or tname == "ptr":
        result = 4
    elif tname == "int64":
        result = 8
    elif tname == "float64":
        result = 8
    elif tname == "int":
        result = 4
    elif tname == "float":
        result = 4
    elif tname == "bool":
        result = 4
    elif tname == "string":
        result = 4
    elif tname == "void":
        result = 0
    else:
        result = 4

proc isFloatNodeCG(node: Node): bool =
  result = node.kind in {nkFloat, nkFAdd, nkFSub, nkFMul, nkFDiv}
  if not result and node.kind == nkIdent:
    result = varTypeMapping.getOrDefault(node.name, "") == "float"
  if not result and node.kind == nkStructGet:
    var structTypeName = ""
    if node.structGetObj != nil and node.structGetObj.kind == nkIdent:
      structTypeName = varTypeMapping.getOrDefault(node.structGetObj.name, node.structGetObj.name)
    if structTypeName.startsWith("ptr "):
      structTypeName = structTypeName[4..^1]
    if structDefs.hasKey(structTypeName):
      let sd = structDefs[structTypeName]
      for f in sd.fields:
        if f.name == node.structGetField:
          result = f.fieldType == "float"
          break

proc gen(node: Node) =
    if node == nil: return
    case node.kind
    of nkInt:
        bytecode.add(opPush.uint8)
        writeInt32(node.intVal)
    of nkInt64:
        bytecode.add(opPush64.uint8)
        writeInt64(node.int64Val)
    of nkFloat:
        bytecode.add(opPushFlt.uint8)
        writeFloat(node.floatValNode)
    of nkTrue:
        bytecode.add(opPushBool.uint8)
        writeInt32(1)
    of nkFalse:
        bytecode.add(opPushBool.uint8)
        writeInt32(0)
    of nkBool: discard
    of nkNil:
        bytecode.add(opPush.uint8)
        writeInt32(0)
    of nkString:
        var idx = -1
        for i, s in stringPool:
            if s == node.strValNode:
                idx = i
                break
        if idx == -1:
            idx = stringPool.len
            stringPool.add(node.strValNode)
        bytecode.add(opPushStr.uint8)
        writeInt32(idx)
    of nkInput:
        bytecode.add(opInput.uint8)
    of nkIdent:
        if not symTable.hasKey(node.name):
            symTable[node.name] = nextAddr
            inc nextAddr
        bytecode.add(opLoad.uint8)
        writeInt32(symTable[node.name])
    of nkStrCat:
        gen(node.left)
        gen(node.right)
        bytecode.add(opStrCat.uint8)
    of nkStrEq:
        gen(node.left)
        gen(node.right)
        bytecode.add(opStrEq.uint8)
    of nkStrLen:
        gen(node.valNode)
        bytecode.add(opStrLen.uint8)
    of nkStrGet:
        gen(node.valNode)
        bytecode.add(opStrGet.uint8)
    of nkAdd, nkSub, nkMul, nkDiv, nkMod, nkAnd, nkOr, nkXor, nkShl, nkShr, nkEq, nkNe, nkLt, nkGt, nkLe, nkGe, nkFAdd, nkFSub, nkFMul, nkFDiv:
        gen(node.left)
        gen(node.right)
        let isFloatOp = node.kind in {nkFAdd, nkFSub, nkFMul, nkFDiv} or
                        (node.kind in {nkAdd, nkSub, nkMul, nkDiv} and
                         (isFloatNodeCG(node.left) or isFloatNodeCG(node.right)))
        let op = if isFloatOp:
                   case node.kind
                   of nkAdd, nkFAdd: opFAdd
                   of nkSub, nkFSub: opFSub
                   of nkMul, nkFMul: opFMul
                   of nkDiv, nkFDiv: opFDiv
                   else: opNoise
                 else:
                   case node.kind
                   of nkAdd: opAdd
                   of nkSub: opSub
                   of nkMul: opMul
                   of nkDiv: opDiv
                   of nkMod: opMod
                   of nkAnd: opAnd
                   of nkOr: opOr
                   of nkXor: opXor
                   of nkShl: opShl
                   of nkShr: opShr
                   of nkEq: opEq
                   of nkNe: opNe
                   of nkLt: opLt
                   of nkGt: opGt
                   of nkLe: opLe
                   of nkGe: opGe
                   of nkFAdd: opFAdd
                   of nkFSub: opFSub
                   of nkFMul: opFMul
                   of nkFDiv: opFDiv
                   else: opNoise
        bytecode.add(op.uint8)
    of nkNeg:
        bytecode.add(opPush.uint8); writeInt32(0)
        gen(node.valNode)
        bytecode.add(opSub.uint8)
    of nkNot:
        gen(node.valNode)
        bytecode.add(opNot.uint8)
    of nkAssign:
        gen(node.right)
        if not symTable.hasKey(node.left.name):
            symTable[node.left.name] = nextAddr
            inc nextAddr
        bytecode.add(opStore.uint8)
        writeInt32(symTable[node.left.name])
    of nkProgram, nkBlock:
        for child in node.children:
            gen(child)
    of nkPrint:
        gen(node.valNode)
        bytecode.add(opPrint.uint8)
    of nkExit:
        if node.valNode != nil: gen(node.valNode)
        bytecode.add(opExit.uint8)
    of nkJmp:
        bytecode.add(opJmp.uint8)
        writeInt32(node.target)
    of nkJz:
        gen(node.cond)
        bytecode.add(opJz.uint8)
        writeInt32(node.target)
    of nkJudge:
        gen(node.condJudge)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        gen(node.thenBody)
        if node.elseBody != nil:
            bytecode.add(opJmp.uint8)
            let jmpPos = bytecode.len
            bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
            patchInt32(jzPos, bytecode.len)
            gen(node.elseBody)
            patchInt32(jmpPos, bytecode.len)
        else:
            patchInt32(jzPos, bytecode.len)
    of nkIf:
        gen(node.ifCond)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        gen(node.ifBody)
        if node.ifElse != nil:
            bytecode.add(opJmp.uint8)
            let jmpPos = bytecode.len
            bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
            patchInt32(jzPos, bytecode.len)
            gen(node.ifElse)
            patchInt32(jmpPos, bytecode.len)
        else:
            patchInt32(jzPos, bytecode.len)
    of nkIfExpr:
        gen(node.ifExprCond)
        bytecode.add(opJz.uint8)
        let ifeJzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        gen(node.ifExprTrue)
        bytecode.add(opJmp.uint8)
        let ifeJmpPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        patchInt32(ifeJzPos, bytecode.len)
        gen(node.ifExprFalse)
        patchInt32(ifeJmpPos, bytecode.len)
    of nkSpiral:
        let startPos = bytecode.len
        gen(node.condJudge)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        loopBreakStack.add(jzPos)
        loopContinueStack.add(startPos)
        gen(node.thenBody)
        discard loopBreakStack.pop()
        discard loopContinueStack.pop()
        bytecode.add(opAbsolution.uint8)
        bytecode.add(opJmp.uint8)
        writeInt32(startPos)
        patchInt32(jzPos, bytecode.len)
    of nkWhile:
        let startPos = bytecode.len
        gen(node.ifCond)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        loopBreakStack.add(jzPos)
        loopContinueStack.add(startPos)
        gen(node.ifBody)
        discard loopBreakStack.pop()
        discard loopContinueStack.pop()
        bytecode.add(opJmp.uint8)
        writeInt32(startPos)
        patchInt32(jzPos, bytecode.len)
    of nkBreak:
        if loopBreakStack.len > 0:
            bytecode.add(opJmp.uint8)
            let target = loopBreakStack[^1]
            bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
            # Will need to patch this to jump past the loop
            let patchPos = bytecode.len - 4
            patchInt32(patchPos, target)
        else:
            bytecode.add(opBreak.uint8)
    of nkContinue:
        if loopContinueStack.len > 0:
            bytecode.add(opJmp.uint8)
            let target = loopContinueStack[^1]
            writeInt32(target)
        else:
            bytecode.add(opContinue.uint8)
    of nkReturn:
        if node.returnVal != nil: gen(node.returnVal)
        bytecode.add(opReturn.uint8)
    of nkFor:
        let varAddr = if not symTable.hasKey(node.forVar):
            symTable[node.forVar] = nextAddr
            inc nextAddr
            nextAddr - 1
          else:
            symTable[node.forVar]
        bytecode.add(opPush.uint8)
        writeInt32(0)
        bytecode.add(opStore.uint8)
        writeInt32(varAddr)
        let startPos = bytecode.len
        bytecode.add(opLoad.uint8)
        writeInt32(varAddr)
        gen(node.forIter)
        bytecode.add(opLt.uint8)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        loopBreakStack.add(jzPos)
        loopContinueStack.add(startPos)
        gen(node.forBody)
        discard loopBreakStack.pop()
        discard loopContinueStack.pop()
        bytecode.add(opPush.uint8)
        writeInt32(1)
        bytecode.add(opLoad.uint8)
        writeInt32(varAddr)
        bytecode.add(opAdd.uint8)
        bytecode.add(opStore.uint8)
        writeInt32(varAddr)
        bytecode.add(opJmp.uint8)
        writeInt32(startPos)
        patchInt32(jzPos, bytecode.len)
    of nkRite:
        bytecode.add(opJmp.uint8)
        let skipJmpPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        let funcStartAddr = bytecode.len
        funcTable[node.funcName] = funcStartAddr
        for i in countdown(node.args.len - 1, 0):
            if not symTable.hasKey(node.args[i]):
                symTable[node.args[i]] = nextAddr
                inc nextAddr
            bytecode.add(opStore.uint8)
            writeInt32(symTable[node.args[i]])
        gen(node.body)
        bytecode.add(opRet.uint8)
        patchInt32(skipJmpPos, bytecode.len)
    of nkFn:
        bytecode.add(opJmp.uint8)
        let skipJmpPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        let funcStartAddr = bytecode.len
        funcTable[node.fnName] = funcStartAddr
        for i in countdown(node.fnArgs.len - 1, 0):
            if not symTable.hasKey(node.fnArgs[i].name):
                symTable[node.fnArgs[i].name] = nextAddr
                inc nextAddr
            varTypeMapping[node.fnArgs[i].name] = node.fnArgs[i].argType
            bytecode.add(opStore.uint8)
            writeInt32(symTable[node.fnArgs[i].name])
        gen(node.fnBody)
        if node.fnReturnType != "void":
            bytecode.add(opPush.uint8)
            writeInt32(0)
        bytecode.add(opRet.uint8)
        patchInt32(skipJmpPos, bytecode.len)
    of nkOrbit:
        let varAddr = if not symTable.hasKey(node.loopVar):
            symTable[node.loopVar] = nextAddr
            inc nextAddr
            nextAddr - 1
          else:
            symTable[node.loopVar]
        bytecode.add(opPush.uint8)
        writeInt32(0)
        bytecode.add(opStore.uint8)
        writeInt32(varAddr)
        let startPos = bytecode.len
        bytecode.add(opLoad.uint8)
        writeInt32(varAddr)
        gen(node.loopCount)
        bytecode.add(opLt.uint8)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        loopBreakStack.add(jzPos)
        loopContinueStack.add(startPos)
        gen(node.loopBody)
        discard loopBreakStack.pop()
        discard loopContinueStack.pop()
        bytecode.add(opPush.uint8)
        writeInt32(1)
        bytecode.add(opLoad.uint8)
        writeInt32(varAddr)
        bytecode.add(opAdd.uint8)
        bytecode.add(opStore.uint8)
        writeInt32(varAddr)
        bytecode.add(opAbsolution.uint8)
        bytecode.add(opJmp.uint8)
        writeInt32(startPos)
        patchInt32(jzPos, bytecode.len)
    of nkCall:
        for child in node.callArgs: gen(child)
        if funcTable.hasKey(node.callName):
            bytecode.add(opCall.uint8)
            writeInt32(funcTable[node.callName])
        elif node.callName in ["reveal", "print"]:
            bytecode.add(opPrint.uint8)
        elif node.callName in ["confess", "input"]:
            bytecode.add(opInput.uint8)
        elif node.callName == "exit":
            bytecode.add(opExit.uint8)
        elif node.callName == "raw":
            if node.callArgs.len > 0 and node.callArgs[0].kind == nkInt:
                bytecode.add(node.callArgs[0].intVal.uint8)
        else:
            for i, ef in externFuncs:
                if ef.name == node.callName:
                    bytecode.add(opFFICall.uint8)
                    writeInt32(i.int32)
                    break
    of nkExtern:
        externFuncs.add((node.externName, node.externArgs.len))
    of nkMapNew:
        if node.valNode != nil: gen(node.valNode)
        else: (bytecode.add(opPush.uint8); writeInt32(0))
        bytecode.add(opMapNew.uint8)
    of nkMapSet:
        gen(node.mapId); gen(node.keyNode); gen(node.valNodeSet)
        bytecode.add(opMapSet.uint8)
    of nkMapGet:
        gen(node.mapIdGet); gen(node.keyNodeGet)
        bytecode.add(opMapGet.uint8)
    of nkVoid:
        let oldVoid = inVoidBlock
        inVoidBlock = true
        for child in node.children: gen(child)
        inVoidBlock = oldVoid
    of nkUsePython:
        bytecode.add(opSwitchParser.uint8)
        for child in node.children: gen(child)
        bytecode.add(opSwitchParser.uint8)
    of nkRawExec:
        if not inVoidBlock:
            raise newException(ValueError, "Fatal Error: Desecration of Sacred Logic")
        gen(node.valNode)
        bytecode.add(opRawExec.uint8)
    of nkGetArg:
        gen(node.valNode)
        bytecode.add(opGetArg.uint8)
    of nkOpen:
        gen(node.valNode)
        bytecode.add(opOpen.uint8)
    of nkRead:
        gen(node.valNode)
        bytecode.add(opRead.uint8)
    of nkClose:
        gen(node.valNode)
        bytecode.add(opClose.uint8)
    of nkWrite:
        gen(node.writeVal)
        gen(node.writeFid)
        bytecode.add(opWrite.uint8)
    of nkStigma:
        gen(node.children[0])
        var endJmpTargets: seq[int] = @[]
        for i in 1 ..< node.children.len:
            let branch = node.children[i]
            if branch.kind == nkFate:
                if branch.fateVal != nil:
                    bytecode.add(opDup.uint8)
                    gen(branch.fateVal)
                    bytecode.add(opEq.uint8)
                    bytecode.add(opJz.uint8)
                    let skipBranchJmp = bytecode.len
                    bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
                    gen(branch.fateBody)
                    bytecode.add(opJmp.uint8)
                    let endJmp = bytecode.len
                    bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
                    endJmpTargets.add(endJmp)
                    patchInt32(skipBranchJmp, bytecode.len)
                else:
                    gen(branch.fateBody)
        let cleanupAddr = bytecode.len
        bytecode.add(opPop.uint8)
        for target in endJmpTargets:
            patchInt32(target, cleanupAddr)
    of nkFate: discard
    of nkEncrypt:
        gen(node.valNode)
        bytecode.add(opEncrypt.uint8)
    of nkEvolve:
        gen(node.valNode)
        bytecode.add(opEvolve.uint8)
    of nkHistoryHash:
        bytecode.add(opHistoryHash.uint8)
    of nkInitEngine:
        gen(node.valNode)
        bytecode.add(opInitEngine.uint8)
    of nkCompile:
        gen(node.valNode)
        bytecode.add(opCompile.uint8)
    of nkCopyAll:
        gen(node.copySrc)
        gen(node.copyDst)
        bytecode.add(opCopyAll.uint8)
    of nkWriteBlock:
        gen(node.writeVal)
        gen(node.writeFid)
        bytecode.add(opWriteBlock.uint8)
    of nkListAppend:
        gen(node.listAppendListId)
        gen(node.listAppendVal)
        bytecode.add(opListAppend.uint8)
    of nkListGet:
        gen(node.listGetListId)
        gen(node.listGetIndex)
        bytecode.add(opListGet.uint8)
    of nkArrayNew:
        if node.arrayNewSize != nil: gen(node.arrayNewSize)
        else: (bytecode.add(opPush.uint8); writeInt32(0))
        if node.arrayNewInit != nil: gen(node.arrayNewInit)
        bytecode.add(opArrayNew.uint8)
    of nkArrayGet:
        gen(node.arrayGetArr)
        gen(node.arrayGetIdx)
        bytecode.add(opArrayGet.uint8)
    of nkArraySet:
        gen(node.arraySetVal)
        gen(node.arraySetArr)
        gen(node.arraySetIdx)
        bytecode.add(opArraySet.uint8)
    of nkArrayLen:
        gen(node.arrayLenArr)
        bytecode.add(opArrayLen.uint8)
    of nkStructDef:
        var cumulativeOffsets: seq[int] = @[]
        var runningOffset = 0
        for f in node.structFields:
            cumulativeOffsets.add(runningOffset)
            runningOffset += typeSize(f.fieldType)
        structDefs[node.structName] = (node.structFields, runningOffset, cumulativeOffsets)
    of nkStructNew:
        if structDefs.hasKey(node.structNewName):
            let sd = structDefs[node.structNewName]
            bytecode.add(opPush.uint8)
            writeInt32(sd.size)
            bytecode.add(opAlloc.uint8)
            for i, arg in node.structNewArgs:
                let fieldOff = if i < sd.offsets.len: sd.offsets[i] else: i * 4
                bytecode.add(opDup.uint8)
                bytecode.add(opPush.uint8)
                writeInt32(fieldOff)
                gen(arg)
                bytecode.add(opPtrWrite.uint8)
    of nkStructGet:
        gen(node.structGetObj)
        var structTypeName = ""
        if node.structGetObj.kind == nkIdent:
            structTypeName = varTypeMapping.getOrDefault(node.structGetObj.name, node.structGetObj.name)
        if structTypeName.startsWith("ptr "):
            structTypeName = structTypeName[4..^1]
        if structDefs.hasKey(structTypeName):
            let sd = structDefs[structTypeName]
            var fieldOff = 0
            for i, f in sd.fields:
                if f.name == node.structGetField:
                    fieldOff = if i < sd.offsets.len: sd.offsets[i] else: i * 4
                    break
            bytecode.add(opPush.uint8)
            writeInt32(fieldOff)
            bytecode.add(opPtrRead.uint8)
    of nkStructSet:
        gen(node.structSetObj)
        var structTypeName = ""
        if node.structSetObj.kind == nkIdent:
            structTypeName = varTypeMapping.getOrDefault(node.structSetObj.name, node.structSetObj.name)
        elif node.structSetObj.kind == nkStructGet:
            if node.structSetObj.structGetObj != nil and node.structSetObj.structGetObj.kind == nkIdent:
                structTypeName = varTypeMapping.getOrDefault(node.structSetObj.structGetObj.name, node.structSetObj.structGetObj.name)
        if structTypeName.startsWith("ptr "):
            structTypeName = structTypeName[4..^1]
        if structDefs.hasKey(structTypeName):
            let sd = structDefs[structTypeName]
            var fieldOff = 0
            for i, f in sd.fields:
                if f.name == node.structSetField:
                    fieldOff = if i < sd.offsets.len: sd.offsets[i] else: i * 4
                    break
            bytecode.add(opPush.uint8)
            writeInt32(fieldOff)
            gen(node.structSetVal)
            bytecode.add(opPtrWrite.uint8)
    of nkAlloc:
        if node.allocSize != nil and node.allocSize.kind == nkIdent and structDefs.hasKey(node.allocSize.name):
            let sd = structDefs[node.allocSize.name]
            bytecode.add(opPush.uint8)
            writeInt32(sd.size)
        else:
            gen(node.allocSize)
        bytecode.add(opAlloc.uint8)
    of nkFree:
        gen(node.freePtr)
        bytecode.add(opFree.uint8)
    of nkAddr:
        if node.addrTarget.kind == nkIdent:
            if not symTable.hasKey(node.addrTarget.name):
                symTable[node.addrTarget.name] = nextAddr
                inc nextAddr
            bytecode.add(opPush.uint8)
            writeInt32(symTable[node.addrTarget.name])
            bytecode.add(opAddr.uint8)
    of nkPtrRead:
        gen(node.ptrReadExpr)
        if node.ptrReadOffset != nil: gen(node.ptrReadOffset)
        else: (bytecode.add(opPush.uint8); writeInt32(0))
        bytecode.add(opPtrRead.uint8)
    of nkPtrWrite:
        gen(node.ptrWriteExpr)
        if node.ptrWriteOffset != nil: gen(node.ptrWriteOffset)
        else: (bytecode.add(opPush.uint8); writeInt32(0))
        gen(node.ptrWriteVal)
        bytecode.add(opPtrWrite.uint8)
    of nkSizeof:
        if node.sizeofType != nil:
            if node.sizeofType.kind == nkIdent:
                let tname = node.sizeofType.name
                if structDefs.hasKey(tname):
                    bytecode.add(opPush.uint8)
                    writeInt32(structDefs[tname].size)
                else:
                    bytecode.add(opPush.uint8)
                    writeInt32(typeSize(tname))
            else:
                bytecode.add(opPush.uint8)
                writeInt32(4)
    of nkImport:
        let content = readFile(node.path)
        var impLexer = tokenize(content)
        var impParser = Parser(tokens: impLexer, pos: 0)
        let impAst = parseProgram(impParser)
        for child in impAst.children:
            gen(child)
    of nkLet, nkVar:
        if node.varDeclVal != nil:
            gen(node.varDeclVal)
        if not symTable.hasKey(node.varDeclName):
            symTable[node.varDeclName] = nextAddr
            inc nextAddr
        if node.varDeclVal != nil:
            bytecode.add(opStore.uint8)
            writeInt32(symTable[node.varDeclName])
        if node.varDeclType != "":
            varTypeMapping[node.varDeclName] = node.varDeclType
        elif node.varDeclVal != nil and node.varDeclVal.kind == nkAlloc and
             node.varDeclVal.allocSize != nil and node.varDeclVal.allocSize.kind == nkIdent:
            varTypeMapping[node.varDeclName] = node.varDeclVal.allocSize.name
    of nkModule:
        for child in node.children:
            gen(child)
    of nkStruct, nkPub, nkAs:
        discard
    of nkEnum:
        discard
    of nkType:
        discard
    of nkPtr:
        discard

proc generateProgram*(node: Node): (seq[uint8], seq[string], seq[string]) =
    symTable = initTable[string, int]()
    funcTable = initTable[string, int]()
    stringPool = @[]
    nextAddr = 0
    bytecode = @[]
    structDefs = initTable[string, tuple[fields: seq[tuple[name: string, fieldType: string]], size: int, offsets: seq[int]]]()
    externFuncs = @[]
    loopBreakStack = @[]
    loopContinueStack = @[]
    varTypeMapping = initTable[string, string]()
    gen(node)
    bytecode.add(opExit.uint8)
    let externNames = externFuncs.mapIt(it.name)
    return (bytecode, stringPool, externNames)

proc generate*(node: Node): seq[uint8] =
    let oldBytecode = bytecode
    bytecode = @[]
    gen(node)
    result = bytecode
    bytecode = oldBytecode
