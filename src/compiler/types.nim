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
        tkFloat, tkInt64,
        tkLBkt, tkRBkt, tkSemicolon,
        tkBool, tkTrue, tkFalse,
        tkIf, tkElif, tkElse, tkWhile, tkFor, tkIn,
        tkBreak, tkContinue, tkReturn, tkNot,
        tkStruct, tkFn, tkLet, tkVar, tkNil,
        tkAs, tkSizeof, tkAlloc, tkFree,
        tkExtern, tkPtr, tkAddr, tkDot,
        tkArrow, tkModule, tkPub, tkEnum, tkType, tkMod

    Token* = object
        kind*: TokenKind
        val*: int
        val64*: int64
        floatVal*: float32
        name*: string
        strVal*: string

    NodeKind* = enum
        nkInt, nkString, nkInput, nkAdd, nkSub, nkMul, nkDiv, nkMod, nkAnd, nkOr,
        nkIdent, nkAssign, nkProgram, nkPrint, nkExit,
        nkJmp, nkJz,
        nkImport, nkMapNew, nkMapSet, nkMapGet,
        nkJudge, nkBlock, nkSpiral, nkRite, nkCall,
        nkEq, nkNe, nkLt, nkGt, nkLe, nkGe,
        nkVoid, nkUsePython, nkRawExec,
        nkGetArg, nkOpen, nkRead, nkClose, nkWrite,
        nkStigma, nkFate,
        nkXor, nkShl, nkShr,
        nkCopyAll, nkEncrypt, nkWriteBlock, nkEvolve,
        nkHistoryHash, nkInitEngine, nkCompile, nkListAppend,
        nkOrbit,
        nkFloat, nkInt64, nkListGet,
        nkFAdd, nkFSub, nkFMul, nkFDiv,
        nkStrCat, nkStrEq, nkStrLen, nkStrGet,
        nkBool, nkTrue, nkFalse,
        nkNeg, nkNot,
        nkIf, nkWhile, nkFor,
        nkBreak, nkContinue, nkReturn,
        nkStruct, nkStructNew, nkStructGet, nkStructSet,
        nkStructDef, nkFn,
        nkLet, nkVar, nkNil,
        nkAs, nkSizeof, nkAlloc, nkFree,
        nkExtern, nkPtr, nkAddr,
        nkArrayNew, nkArrayGet, nkArraySet, nkArrayLen,
        nkModule, nkPub, nkEnum, nkType,
        nkPtrRead, nkPtrWrite,
        nkIfExpr

    Node* = ref object
        case kind*: NodeKind
        of nkInt: intVal*: int
        of nkInt64: int64Val*: int64
        of nkFloat: floatValNode*: float32
        of nkBool: boolVal*: bool
        of nkString: strValNode*: string
        of nkInput, nkNil, nkBreak, nkContinue, nkTrue, nkFalse, nkStruct, nkPub: discard
        of nkIdent: name*: string
        of nkCall:
            callName*: string
            callArgs*: seq[Node]
        of nkImport: path*: string
        of nkReturn: returnVal*: Node
        of nkAlloc: allocSize*: Node
        of nkFree: freePtr*: Node
        of nkAddr: addrTarget*: Node
        of nkSizeof: sizeofType*: Node
        of nkAs:
            asExpr*: Node
            asTypeName*: string
        of nkStructDef:
            structName*: string
            structFields*: seq[tuple[name: string, fieldType: string]]
        of nkStructNew:
            structNewName*: string
            structNewArgs*: seq[Node]
        of nkStructGet:
            structGetObj*: Node
            structGetField*: string
        of nkStructSet:
            structSetObj*: Node
            structSetField*: string
            structSetVal*: Node
        of nkFn:
            fnName*: string
            fnArgs*: seq[tuple[name: string, argType: string]]
            fnReturnType*: string
            fnBody*: Node
        of nkLet, nkVar:
            varDeclName*: string
            varDeclType*: string
            varDeclVal*: Node
        of nkExtern:
            externName*: string
            externArgs*: seq[string]
            externReturn*: string
        of nkPtr:
            ptrBaseType*: string
        of nkPtrRead:
            ptrReadExpr*: Node
            ptrReadOffset*: Node
        of nkPtrWrite:
            ptrWriteExpr*: Node
            ptrWriteOffset*: Node
            ptrWriteVal*: Node
        of nkArrayNew:
            arrayNewSize*: Node
            arrayNewInit*: Node
        of nkArrayGet:
            arrayGetArr*: Node
            arrayGetIdx*: Node
        of nkArraySet:
            arraySetArr*: Node
            arraySetIdx*: Node
            arraySetVal*: Node
        of nkArrayLen:
            arrayLenArr*: Node
        of nkAdd, nkSub, nkMul, nkDiv, nkMod, nkAnd, nkOr, nkAssign, nkEq, nkNe, nkLt, nkGt, nkLe, nkGe, nkXor, nkShl, nkShr, nkFAdd, nkFSub, nkFMul, nkFDiv, nkStrCat, nkStrEq:
            left*, right*: Node
        of nkProgram, nkBlock, nkVoid, nkUsePython, nkStigma, nkModule:
            children*: seq[Node]
        of nkFate:
            fateVal*: Node
            fateBody*: Node
        of nkPrint, nkExit, nkMapNew, nkRawExec, nkGetArg, nkOpen, nkRead, nkClose, nkEncrypt, nkEvolve, nkHistoryHash, nkInitEngine, nkCompile, nkNeg, nkNot, nkStrLen, nkStrGet:
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
        of nkIf, nkWhile:
            ifCond*: Node
            ifBody*: Node
            ifElse*: Node
        of nkFor:
            forVar*: string
            forIter*: Node
            forBody*: Node
        of nkRite:
            funcName*: string
            args*: seq[string]
            body*: Node
        of nkOrbit:
            loopVar*: string
            loopCount*: Node
            loopBody*: Node
        of nkEnum:
            enumName*: string
            enumVariants*: seq[tuple[name: string, val: int]]
        of nkType:
            typeAlias*: string
            typeTarget*: string
        of nkIfExpr:
            ifExprCond*: Node
            ifExprTrue*: Node
            ifExprFalse*: Node

    StructDef* = object
        name*: string
        fields*: seq[tuple[name: string, fieldType: string, offset: int]]
        size*: int

    ExternFunc* = object
        name*: string
        argTypes*: seq[string]
        returnType*: string
