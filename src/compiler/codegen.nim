# src/compiler/codegen.nim
import types, ../common/isa, tables, lexer, parser

var symTable: Table[string, int]
var funcTable: Table[string, int]
var stringPool: seq[string]
var nextAddr = 0
var bytecode: seq[uint8]
var inVoidBlock = false

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
    of nkAdd, nkSub, nkMul, nkDiv, nkXor, nkShl, nkShr, nkEq, nkNe, nkLt, nkGt, nkLe, nkGe, nkFAdd, nkFSub, nkFMul, nkFDiv:
        gen(node.left)
        gen(node.right)
        let op = case node.kind
                 of nkAdd: opAdd
                 of nkSub: opSub
                 of nkMul: opMul
                 of nkDiv: opDiv
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
    of nkSpiral:
        let startPos = bytecode.len
        gen(node.condJudge)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        gen(node.thenBody)
        bytecode.add(opAbsolution.uint8)
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
    of nkOrbit:
        let varAddr = if not symTable.hasKey(node.loopVar):
            symTable[node.loopVar] = nextAddr
            inc nextAddr
            nextAddr - 1
          else:
            symTable[node.loopVar]
        # init i = 0
        bytecode.add(opPush.uint8)
        writeInt32(0)
        bytecode.add(opStore.uint8)
        writeInt32(varAddr)
        let startPos = bytecode.len
        # check i < count
        bytecode.add(opLoad.uint8)
        writeInt32(varAddr)
        gen(node.loopCount)
        bytecode.add(opLt.uint8)
        bytecode.add(opJz.uint8)
        let jzPos = bytecode.len
        bytecode.add(@[0x00.uint8, 0x00, 0x00, 0x00])
        gen(node.loopBody)
        # i += 1
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
        bytecode.add(opSwitchParser.uint8) # ISA_SWITCH_PARSER
        # In a real implementation, we would load python_trans.atb here
        for child in node.children: gen(child)
        bytecode.add(opSwitchParser.uint8) # Switch back or finish
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
        # push value first, then fid (VM pops fid then val)
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
    of nkCheck:
        bytecode.add(opCheck.uint8)
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
    of nkImport:
        let content = readFile(node.path)
        var impLexer = tokenize(content)
        var impParser = Parser(tokens: impLexer, pos: 0)
        let impAst = parseProgram(impParser)
        for child in impAst.children:
            gen(child)

proc generateProgram*(node: Node): (seq[uint8], seq[string]) =
    symTable = initTable[string, int]()
    funcTable = initTable[string, int]()
    stringPool = @[]
    nextAddr = 0
    bytecode = @[]
    gen(node)
    bytecode.add(opExit.uint8)
    return (bytecode, stringPool)

proc generate*(node: Node): seq[uint8] =
    let oldBytecode = bytecode
    bytecode = @[]
    gen(node)
    result = bytecode
    bytecode = oldBytecode
