# src/compiler/types.nim

type
    TokenKind* = enum 
        tkInt, tkPlus, tkMinus, tkMul, tkDiv,
        tkLPar, tkRPar, tkIdent, tkAssign, tkEOF,
        tkPrint, tkExit, tkJmp, tkJz,
        tkImport, tkString, tkComma,
        tkJudge, tkSeal, tkColon, tkIndent, tkDedent, tkNewline,
        tkSpiral, tkRite,
        tkEq, tkNe, tkLt, tkGt, tkLe, tkGe,
        tkVoid, tkUsePython, tkRaw, tkLBrace, tkRBrace,
        tkGetArg, tkOpen, tkRead, tkClose, tkWrite,
        tkStigma, tkFate, tkAbyss,
        tkXor, tkShl, tkShr, tkOrbit,
        # V11
        tkFloat, tkInt64,
        tkLBkt, tkRBkt, tkSemicolon,

    Token* = object
        kind*: TokenKind
        val*: int
        val64*: int64
        floatVal*: float32
        name*: string
        strVal*: string

    NodeKind* = enum 
        nkInt, nkString, nkInput, nkAdd, nkSub, nkMul, nkDiv,
        nkIdent, nkAssign, nkProgram, nkPrint, nkExit,
        nkJmp, nkJz,
        nkImport, nkMapNew, nkMapSet, nkMapGet,
        nkJudge, nkBlock, nkSpiral, nkRite, nkCall,
        nkEq, nkNe, nkLt, nkGt, nkLe, nkGe,
        nkVoid, nkUsePython, nkRawExec,
        nkGetArg, nkOpen, nkRead, nkClose, nkWrite,
        nkStigma, nkFate,
        nkXor, nkShl, nkShr,
        nkCopyAll, nkCheck, nkEncrypt, nkWriteBlock, nkEvolve,
        nkHistoryHash, nkInitEngine, nkCompile, nkListAppend,
        nkOrbit,
        # V11
        nkFloat, nkInt64, nkListGet,
        nkFAdd, nkFSub, nkFMul, nkFDiv,
        nkStrCat

    Node* = ref object
        case kind*: NodeKind
        of nkInt: intVal*: int
        of nkInt64: int64Val*: int64
        of nkFloat: floatValNode*: float32
        of nkString: strValNode*: string
        of nkInput: discard
        of nkIdent: name*: string
        of nkCall:
            callName*: string
            callArgs*: seq[Node]
        of nkImport: path*: string
        of nkAdd, nkSub, nkMul, nkDiv, nkAssign, nkEq, nkNe, nkLt, nkGt, nkLe, nkGe, nkXor, nkShl, nkShr, nkFAdd, nkFSub, nkFMul, nkFDiv, nkStrCat:
            left*, right*: Node
        of nkProgram, nkBlock, nkVoid, nkUsePython, nkStigma:
            children*: seq[Node]
        of nkFate:
            fateVal*: Node
            fateBody*: Node
        of nkPrint, nkExit, nkMapNew, nkRawExec, nkGetArg, nkOpen, nkRead, nkClose, nkEncrypt, nkEvolve, nkHistoryHash, nkInitEngine, nkCompile, nkCheck:
            valNode*: Node
        of nkWrite, nkWriteBlock:
            writeFid*: Node
            writeVal*: Node
        of nkCopyAll:
            copySrc*: Node
            copyDst*: Node
        of nkListAppend:
            listAppendListId*: Node
            listAppendVal*: Node
        of nkListGet:
            listGetListId*: Node
            listGetIndex*: Node
        of nkMapSet:
            mapId*, keyNode*, valNodeSet*: Node
        of nkMapGet:
            mapIdGet*, keyNodeGet*: Node
        of nkJmp, nkJz:
            target*: int
            cond*: Node
        of nkJudge, nkSpiral:
            condJudge*: Node
            thenBody*: Node
            elseBody*: Node
        of nkRite:
            funcName*: string
            args*: seq[string]
            body*: Node
        of nkOrbit:
            loopVar*: string
            loopCount*: Node
            loopBody*: Node
