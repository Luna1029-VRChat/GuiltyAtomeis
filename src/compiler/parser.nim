import types, sets, tables

type Parser* = object
    tokens*: seq[Token]
    pos*: int
    floatVars*: HashSet[string]
    stringVars*: HashSet[string]
    structDefs*: Table[string, StructDef]
    floatFieldNames*: HashSet[string]
    externFuncs*: seq[ExternFunc]
    loopDepth*: int
    currentModule*: string

proc peek(p: Parser): Token =
    if p.pos >= p.tokens.len: return Token(kind: tkEOF)
    return p.tokens[p.pos]
proc next(p: var Parser) =
    inc p.pos
proc expect(p: var Parser, kind: TokenKind) =
    if p.peek.kind != kind:
        raise newException(ValueError, "Expected " & $kind & " but got " & $p.peek.kind)
    p.next()

proc parseExpr(p: var Parser): Node

proc skipNewlines(p: var Parser) =
    while p.peek.kind == tkNewline:
        p.next()

proc skipNewlinesAndIndents(p: var Parser) =
    while p.peek.kind in {tkNewline, tkIndent, tkDedent}:
        p.next()

proc expectFieldName(p: var Parser): string =
    if p.peek.kind == tkIdent:
        result = p.peek.name
        p.next()
    elif p.peek.kind == tkType:
        result = "type"
        p.next()
    else:
        raise newException(ValueError, "Expected field name after '.'")

proc parseFactor(p: var Parser): Node =
    let t = p.peek
    case t.kind
    of tkInt:
        p.next()
        return Node(kind: nkInt, intVal: t.val)
    of tkFloat:
        p.next()
        return Node(kind: nkFloat, floatValNode: t.floatVal)
    of tkInt64:
        p.next()
        return Node(kind: nkInt64, int64Val: t.val64)
    of tkString:
        p.next()
        return Node(kind: nkString, strValNode: t.strVal)
    of tkTrue:
        p.next()
        return Node(kind: nkTrue)
    of tkFalse:
        p.next()
        return Node(kind: nkFalse)
    of tkNil:
        p.next()
        return Node(kind: nkNil)
    of tkIdent:
        p.next()
        if t.name == "confess" or t.name == "input":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after " & t.name)
            p.next()
            if p.peek.kind != tkRPar: discard parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkInput)
        elif t.name == "map_new":
            p.expect tkLPar
            var size: Node = nil
            if p.peek.kind != tkRPar: size = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkMapNew, valNode: size)
        elif t.name == "map_set":
            p.expect tkLPar; let mid = parseExpr(p)
            p.expect tkComma; let key = parseExpr(p)
            p.expect tkComma; let val = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkMapSet, mapId: mid, keyNode: key, valNodeSet: val)
        elif t.name == "map_get":
            p.expect tkLPar; let mid = parseExpr(p)
            p.expect tkComma; let key = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkMapGet, mapIdGet: mid, keyNodeGet: key)
        elif t.name == "copy_all":
            p.expect tkLPar; let src = parseExpr(p)
            p.expect tkComma; let dst = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkCopyAll, copySrc: src, copyDst: dst)
        elif t.name == "encrypt":
            p.expect tkLPar; let val = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkEncrypt, valNode: val)
        elif t.name == "evolve":
            p.expect tkLPar; let val = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkEvolve, valNode: val)
        elif t.name == "history_hash":
            p.expect tkLPar; p.expect tkRPar
            return Node(kind: nkHistoryHash, valNode: nil)
        elif t.name == "init_engine":
            p.expect tkLPar; let val = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkInitEngine, valNode: val)
        elif t.name == "compile":
            p.expect tkLPar; let val = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkCompile, valNode: val)
        elif t.name == "list_append":
            p.expect tkLPar; let lid = parseExpr(p)
            p.expect tkComma; let lval = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkListAppend, listAppendListId: lid, listAppendVal: lval)
        elif t.name == "write_block":
            p.expect tkLPar; let fid = parseExpr(p)
            p.expect tkComma; let wval = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkWriteBlock, writeFid: fid, writeVal: wval)
        elif t.name == "sizeof":
            p.expect tkLPar; let expr = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkSizeof, sizeofType: expr)
        elif t.name == "alloc":
            p.expect tkLPar; let sz = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkAlloc, allocSize: sz)
        elif t.name == "free":
            p.expect tkLPar; let ptrVal = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkFree, freePtr: ptrVal)
        elif t.name == "addr":
            p.expect tkLPar; let target = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkAddr, addrTarget: target)
        elif t.name == "len" and p.peek.kind == tkLPar:
            p.next()
            let arr = parseExpr(p)
            p.expect tkRPar
            return Node(kind: nkArrayLen, arrayLenArr: arr)
        elif p.peek.kind == tkLPar:
            p.next()
            skipNewlinesAndIndents(p)
            var args: seq[Node] = @[]
            while p.peek.kind != tkRPar and p.peek.kind != tkEOF:
                args.add(p.parseExpr())
                skipNewlinesAndIndents(p)
                if p.peek.kind == tkComma:
                    p.next()
                    skipNewlinesAndIndents(p)
            p.expect tkRPar
            return Node(kind: nkCall, callName: t.name, callArgs: args)
        if p.peek.kind == tkLBkt:
            p.next()
            let idx = p.parseExpr()
            if p.peek.kind == tkColon:
                p.next()
                discard p.parseExpr()
            p.expect tkRBkt
            return Node(kind: nkArrayGet, arrayGetArr: Node(kind: nkIdent, name: t.name), arrayGetIdx: idx)
        if p.peek.kind == tkDot:
            p.next()
            let field = expectFieldName(p)
            return Node(kind: nkStructGet, structGetObj: Node(kind: nkIdent, name: t.name), structGetField: field)
        return Node(kind: nkIdent, name: t.name)
    of tkGetArg, tkOpen, tkRead, tkClose, tkRaw:
        let tkind = t.kind
        p.next()
        p.expect tkLPar
        var val: Node = nil
        if p.peek.kind != tkRPar: val = parseExpr(p)
        p.expect tkRPar
        case tkind:
            of tkGetArg: return Node(kind: nkGetArg, valNode: val)
            of tkOpen: return Node(kind: nkOpen, valNode: val)
            of tkRead: return Node(kind: nkRead, valNode: val)
            of tkClose: return Node(kind: nkClose, valNode: val)
            of tkRaw: return Node(kind: nkRawExec, valNode: val)
            else: return Node(kind: nkRawExec, valNode: val)
    of tkWrite:
        p.next()
        p.expect tkLPar
        let fid = parseExpr(p)
        p.expect tkComma
        let wval = parseExpr(p)
        p.expect tkRPar
        return Node(kind: nkWrite, writeFid: fid, writeVal: wval)
    of tkSizeof:
        p.next()
        p.expect tkLPar
        let expr = parseExpr(p)
        p.expect tkRPar
        return Node(kind: nkSizeof, sizeofType: expr)
    of tkAlloc:
        p.next()
        p.expect tkLPar
        let sz = parseExpr(p)
        p.expect tkRPar
        return Node(kind: nkAlloc, allocSize: sz)
    of tkFree:
        p.next()
        p.expect tkLPar
        let ptrExpr = parseExpr(p)
        p.expect tkRPar
        return Node(kind: nkFree, freePtr: ptrExpr)
    of tkAddr:
        p.next()
        p.expect tkLPar
        let target = parseExpr(p)
        p.expect tkRPar
        return Node(kind: nkAddr, addrTarget: target)
    of tkLPar:
        p.next()
        result = parseExpr(p)
        p.expect tkRPar
    of tkPtr:
        p.next()
        if p.peek.kind == tkIdent:
            let baseType = p.peek.name
            p.next()
            return Node(kind: nkPtr, ptrBaseType: baseType)
        raise newException(ValueError, "Expected type name after ptr")
    else:
        raise newException(ValueError, "Expected expression but got " & $t.kind & " at pos " & $p.pos)

proc parseUnary(p: var Parser): Node =
    if p.peek.kind in {tkMinus, tkNot}:
        let op = p.peek.kind
        p.next()
        let expr = parseUnary(p)
        if op == tkMinus:
            return Node(kind: nkNeg, valNode: expr)
        else:
            return Node(kind: nkNot, valNode: expr)
    result = parseFactor(p)
    while p.peek.kind in {tkLBkt, tkDot, tkLPar}:
        if p.peek.kind == tkLPar:
            p.next()
            skipNewlinesAndIndents(p)
            var args: seq[Node] = @[]
            while p.peek.kind != tkRPar and p.peek.kind != tkEOF:
                args.add(p.parseExpr())
                skipNewlinesAndIndents(p)
                if p.peek.kind == tkComma:
                    p.next()
                    skipNewlinesAndIndents(p)
            p.expect tkRPar
            if result.kind == nkIdent:
                result = Node(kind: nkCall, callName: result.name, callArgs: args)
            else:
                result = Node(kind: nkCall, callName: "", callArgs: args)
        elif p.peek.kind == tkLBkt:
            p.next()
            let idx = parseExpr(p)
            if p.peek.kind == tkColon:
                p.next()
                discard parseExpr(p)
            p.expect tkRBkt
            result = Node(kind: nkArrayGet, arrayGetArr: result, arrayGetIdx: idx)
        else:
            p.next()
            let field = expectFieldName(p)
            result = Node(kind: nkStructGet, structGetObj: result, structGetField: field)

proc isFloatNode(n: Node, p: Parser): bool =
    result = n.kind in {nkFloat, nkFAdd, nkFSub, nkFMul, nkFDiv}
    if not result and n.kind == nkIdent:
        result = n.name in p.floatVars

proc isStringNode(n: Node, p: Parser): bool =
    result = n.kind in {nkString, nkStrCat, nkStrEq, nkStrLen, nkStrGet}
    if not result and n.kind == nkIdent:
        result = n.name in p.stringVars

proc parseTerm(p: var Parser): Node =
    result = parseUnary(p)
    while p.peek.kind in {tkMul, tkDiv, tkMod}:
        let op = p.peek.kind
        p.next()
        let right = parseUnary(p)
        if op == tkMod:
            result = Node(kind: nkMod, left: result, right: right)
        elif isFloatNode(result, p) or isFloatNode(right, p):
            if op == tkMul:
                result = Node(kind: nkFMul, left: result, right: right)
            else:
                result = Node(kind: nkFDiv, left: result, right: right)
        else:
            if op == tkMul:
                result = Node(kind: nkMul, left: result, right: right)
            else:
                result = Node(kind: nkDiv, left: result, right: right)

proc parseShift(p: var Parser): Node =
    result = parseTerm(p)
    while p.peek.kind in {tkShl, tkShr}:
        let op = p.peek.kind
        p.next()
        let right = parseTerm(p)
        if op == tkShl:
            result = Node(kind: nkShl, left: result, right: right)
        else:
            result = Node(kind: nkShr, left: result, right: right)

proc parseArith(p: var Parser): Node =
    result = parseShift(p)
    while p.peek.kind in {tkPlus, tkMinus, tkXor}:
        let op = p.peek.kind
        p.next()
        let right = parseShift(p)
        if isStringNode(result, p) or isStringNode(right, p):
            if op == tkPlus:
                if result.kind == nkString and right.kind == nkString:
                    result = Node(kind: nkString, strValNode: result.strValNode & right.strValNode)
                else:
                    result = Node(kind: nkStrCat, left: result, right: right)
            else:
                result = Node(kind: nkXor, left: result, right: right)
        elif isFloatNode(result, p) or isFloatNode(right, p):
            if op == tkPlus:
                result = Node(kind: nkFAdd, left: result, right: right)
            elif op == tkMinus:
                result = Node(kind: nkFSub, left: result, right: right)
            else:
                result = Node(kind: nkXor, left: result, right: right)
        else:
            if op == tkPlus:
                result = Node(kind: nkAdd, left: result, right: right)
            elif op == tkMinus:
                result = Node(kind: nkSub, left: result, right: right)
            else:
                result = Node(kind: nkXor, left: result, right: right)

proc parseComparison(p: var Parser): Node =
    result = parseArith(p)
    if p.peek.kind in {tkEq, tkNe, tkLt, tkGt, tkLe, tkGe}:
        let kind = p.peek.kind
        p.next()
        let right = parseArith(p)
        case kind
        of tkEq: result = Node(kind: nkEq, left: result, right: right)
        of tkNe: result = Node(kind: nkNe, left: result, right: right)
        of tkLt: result = Node(kind: nkLt, left: result, right: right)
        of tkGt: result = Node(kind: nkGt, left: result, right: right)
        of tkLe: result = Node(kind: nkLe, left: result, right: right)
        of tkGe: result = Node(kind: nkGe, left: result, right: right)
        else: discard

proc parseInlineIf(p: var Parser): Node =
    p.next()  # consume 'if'
    let cond = parseExpr(p)
    skipNewlinesAndIndents(p)
    p.expect tkColon
    skipNewlinesAndIndents(p)
    let trueVal = parseExpr(p)
    skipNewlinesAndIndents(p)
    var falseVal: Node = nil
    if p.peek.kind == tkElse:
        p.next()
        if p.peek.kind == tkColon:
            p.next()
        falseVal = parseExpr(p)
    elif p.peek.kind == tkElif:
        falseVal = parseInlineIf(p)
    return Node(kind: nkIfExpr, ifExprCond: cond, ifExprTrue: trueVal, ifExprFalse: falseVal)

proc parseExpr(p: var Parser): Node =
    if p.peek.kind == tkIf:
        return parseInlineIf(p)
    result = parseComparison(p)
    while p.peek.kind == tkIdent and (p.peek.name == "and" or p.peek.name == "or"):
        let isAnd = p.peek.name == "and"
        p.next()
        let right = parseComparison(p)
        if isAnd:
            result = Node(kind: nkAnd, left: result, right: right)
        else:
            result = Node(kind: nkOr, left: result, right: right)

proc parseStatement*(p: var Parser): Node

proc parseBlock(p: var Parser): Node =
    skipNewlines(p)
    if p.peek.kind != tkIndent:
        result = Node(kind: nkBlock, children: @[])
        while true:
            let stmt = p.parseStatement()
            if stmt != nil:
                result.children.add(stmt)
            if p.peek.kind == tkSemicolon:
                p.next()
            else:
                break
        return result
    p.next()
    result = Node(kind: nkBlock, children: @[])
    while p.peek.kind != tkDedent and p.peek.kind != tkEOF:
        let stmt = p.parseStatement()
        if stmt != nil:
            result.children.add(stmt)
        if p.peek.kind == tkSemicolon:
            p.next()
    if p.peek.kind == tkDedent: p.next()

proc parseStigma(p: var Parser): Node =
    p.next()
    let expr = parseExpr(p)
    p.expect tkColon
    skipNewlines(p)
    p.expect tkIndent
    result = Node(kind: nkStigma, children: @[expr])
    while p.peek.kind in {tkFate, tkAbyss}:
        let tkind = p.peek.kind
        p.next()
        var val: Node = nil
        if tkind == tkFate:
            val = parseExpr(p)
        p.expect tkColon
        let body = parseBlock(p)
        result.children.add(Node(kind: nkFate, fateVal: val, fateBody: body))
    if p.peek.kind == tkDedent: p.next()

proc parseOrbit(p: var Parser): Node =
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected identifier after orbit")
    let varName = p.peek.name
    p.next()
    if p.peek.kind != tkIdent or p.peek.name != "in":
        raise newException(ValueError, "Expected 'in' after orbit variable")
    p.next()
    let count = parseExpr(p)
    p.expect tkColon
    let body = parseBlock(p)
    return Node(kind: nkOrbit, loopVar: varName, loopCount: count, loopBody: body)

proc parseTypeTokens(p: var Parser): string =
    result = ""
    if p.peek.kind == tkPtr:
        result = "ptr"
        p.next()
        while p.peek.kind == tkPtr:
            result = result & " ptr"
            p.next()
        if p.peek.kind == tkIdent:
            result = result & " " & p.peek.name
            p.next()
        elif p.peek.kind in {tkInt, tkFloat, tkBool, tkString, tkVoid}:
            let typeName = case p.peek.kind
                           of tkInt: "int"
                           of tkFloat: "float"
                           of tkBool: "bool"
                           of tkString: "string"
                           of tkVoid: "void"
                           else: ""
            result = result & " " & typeName
            p.next()
    elif p.peek.kind in {tkIdent, tkInt, tkFloat, tkBool, tkString, tkVoid}:
        case p.peek.kind
        of tkInt: result = "int"
        of tkFloat: result = "float"
        of tkBool: result = "bool"
        of tkString: result = "string"
        of tkVoid: result = "void"
        else: result = p.peek.name
        p.next()
        # Optional bracket suffix for array types: Type[Size]
        if p.peek.kind == tkLBkt:
            result = result & "["
            p.next()
            if p.peek.kind == tkInt:
                result = result & $p.peek.val
                p.next()
            elif p.peek.kind == tkIdent:
                result = result & p.peek.name
                p.next()
            if p.peek.kind == tkRBkt:
                result = result & "]"
                p.next()
    if result == "": result = "int"

proc parseStruct(p: var Parser): Node =
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected struct name")
    let name = p.peek.name
    p.next()
    p.expect tkColon
    skipNewlines(p)
    p.expect tkIndent
    var fields: seq[tuple[name: string, fieldType: string]] = @[]
    while p.peek.kind notin {tkDedent, tkEOF}:
        if p.peek.kind == tkIdent or p.peek.kind == tkType:
            let fname = (if p.peek.kind == tkType: "type" else: p.peek.name)
            p.next()
            var ftype = "int"
            if p.peek.kind == tkColon:
                p.next()
                ftype = parseTypeTokens(p)
            fields.add((fname, ftype))
        elif p.peek.kind == tkNewline:
            p.next()
        else:
            break
    if p.peek.kind == tkDedent: p.next()
    return Node(kind: nkStructDef, structName: name, structFields: fields)

proc parseFn(p: var Parser): Node =
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected function name")
    let name = p.peek.name
    p.next()
    p.expect tkLPar
    var args: seq[tuple[name: string, argType: string]] = @[]
    while p.peek.kind == tkIdent:
        let aname = p.peek.name
        p.next()
        var atype = "int"
        if p.peek.kind == tkColon:
            p.next()
            atype = parseTypeTokens(p)
        args.add((aname, atype))
        if p.peek.kind == tkComma: p.next()
    p.expect tkRPar
    var returnType = "void"
    if p.peek.kind == tkArrow:
        p.next()
        returnType = parseTypeTokens(p)
        p.expect tkColon
    elif p.peek.kind == tkColon:
        p.next()
        if p.peek.kind in {tkIdent, tkBool, tkInt, tkFloat, tkString, tkVoid, tkPtr}:
            returnType = parseTypeTokens(p)
            p.expect tkColon
    let body = parseBlock(p)
    return Node(kind: nkFn, fnName: name, fnArgs: args, fnReturnType: returnType, fnBody: body)

proc parseExtern(p: var Parser): Node =
    p.next()
    if p.peek.kind != tkFn:
        raise newException(ValueError, "Expected 'fn' after extern")
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected function name")
    let name = p.peek.name
    p.next()
    p.expect tkLPar
    var argTypes: seq[string] = @[]
    while p.peek.kind in {tkIdent, tkPtr, tkBool, tkInt, tkFloat, tkString, tkVoid}:
        let atype = parseTypeTokens(p)
        argTypes.add(atype)
        if p.peek.kind == tkComma: p.next()
    p.expect tkRPar
    var returnType = "void"
    if p.peek.kind == tkArrow:
        p.next()
        returnType = parseTypeTokens(p)
    elif p.peek.kind == tkColon:
        p.next()
        if p.peek.kind in {tkIdent, tkBool, tkInt, tkFloat, tkString, tkVoid, tkPtr}:
            returnType = parseTypeTokens(p)
    return Node(kind: nkExtern, externName: name, externArgs: argTypes, externReturn: returnType)

proc parseEnum(p: var Parser): Node =
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected enum name")
    let name = p.peek.name
    p.next()
    p.expect tkColon
    skipNewlines(p)
    p.expect tkIndent
    var variants: seq[tuple[name: string, val: int]] = @[]
    var nextVal = 0
    while p.peek.kind notin {tkDedent, tkEOF}:
        if p.peek.kind == tkIdent:
            let vname = p.peek.name
            p.next()
            var vval = nextVal
            if p.peek.kind == tkAssign:
                p.next()
                if p.peek.kind == tkInt:
                    vval = p.peek.val
                    p.next()
            variants.add((vname, vval))
            nextVal = vval + 1
        elif p.peek.kind == tkNewline:
            p.next()
        else:
            break
    if p.peek.kind == tkDedent: p.next()
    return Node(kind: nkEnum, enumName: name, enumVariants: variants)

proc parseVarDecl(p: var Parser, kind: TokenKind): Node =
    let isMutable = (kind == tkVar)
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected variable name")
    let name = p.peek.name
    p.next()
    var declType = ""
    if p.peek.kind == tkColon:
        p.next()
        declType = parseTypeTokens(p)
    var initVal: Node = nil
    if p.peek.kind == tkAssign:
        p.next()
        initVal = parseExpr(p)
    if isMutable:
        return Node(kind: nkVar, varDeclName: name, varDeclType: declType, varDeclVal: initVal)
    else:
        return Node(kind: nkLet, varDeclName: name, varDeclType: declType, varDeclVal: initVal)

proc parseIf(p: var Parser): Node =
    p.next()
    let cond = parseExpr(p)
    p.expect tkColon
    let body = parseBlock(p)
    var elseBody: Node = nil
    if p.peek.kind == tkElif:
        elseBody = parseIf(p)
    elif p.peek.kind == tkElse:
        p.next()
        p.expect tkColon
        elseBody = parseBlock(p)
    return Node(kind: nkIf, ifCond: cond, ifBody: body, ifElse: elseBody)

proc parseWhile(p: var Parser): Node =
    inc p.loopDepth
    p.next()
    let cond = parseExpr(p)
    p.expect tkColon
    let body = parseBlock(p)
    dec p.loopDepth
    return Node(kind: nkWhile, ifCond: cond, ifBody: body)

proc parseFor(p: var Parser): Node =
    inc p.loopDepth
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected identifier after for")
    let varName = p.peek.name
    p.next()
    if p.peek.kind == tkIn:
        p.next()
        let iter = parseExpr(p)
        p.expect tkColon
        let body = parseBlock(p)
        dec p.loopDepth
        return Node(kind: nkFor, forVar: varName, forIter: iter, forBody: body)
    else:
        let count = parseExpr(p)
        p.expect tkColon
        let body = parseBlock(p)
        dec p.loopDepth
        return Node(kind: nkOrbit, loopVar: varName, loopCount: count, loopBody: body)

proc parseModule(p: var Parser): Node =
    p.next()
    var name = ""
    if p.peek.kind == tkIdent:
        name = p.peek.name
        p.next()
    p.expect tkColon
    let body = parseBlock(p)
    return Node(kind: nkModule, children: @[Node(kind: nkString, strValNode: name)] & body.children)

proc parseType(p: var Parser): Node =
    p.next()
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected type name")
    let alias = p.peek.name
    p.next()
    p.expect tkAssign
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected target type")
    let target = p.peek.name
    p.next()
    return Node(kind: nkType, typeAlias: alias, typeTarget: target)

proc parseStatement*(p: var Parser): Node =
    let t = p.peek
    case t.kind
    of tkEOF: return nil
    of tkStigma: return parseStigma(p)
    of tkOrbit: return parseOrbit(p)
    of tkIf: return parseIf(p)
    of tkWhile: return parseWhile(p)
    of tkFor: return parseFor(p)
    of tkBreak:
        p.next()
        if p.loopDepth <= 0: raise newException(ValueError, "break outside loop")
        return Node(kind: nkBreak)
    of tkContinue:
        p.next()
        if p.loopDepth <= 0: raise newException(ValueError, "continue outside loop")
        return Node(kind: nkContinue)
    of tkReturn:
        p.next()
        var val: Node = nil
        if p.peek.kind notin {tkEOF, tkNewline, tkDedent, tkSemicolon, tkRPar, tkRBkt, tkRBrace, tkColon, tkVar, tkLet, tkIf, tkWhile, tkFor, tkFn, tkStruct, tkEnum, tkPub, tkModule, tkExtern}:
            val = parseExpr(p)
        return Node(kind: nkReturn, returnVal: val)
    of tkStruct: return parseStruct(p)
    of tkFn: return parseFn(p)
    of tkExtern: return parseExtern(p)
    of tkEnum: return parseEnum(p)
    of tkModule: return parseModule(p)
    of tkType: return parseType(p)
    of tkLet, tkVar: return parseVarDecl(p, t.kind)
    of tkDedent, tkIndent, tkNewline, tkSemicolon:
        if t.kind == tkSemicolon: p.next()
        else: p.next()
        return nil
    of tkImport:
        p.next()
        if p.peek.kind != tkString: raise newException(ValueError, "Expected string path after import")
        let path = p.peek.strVal
        p.next()
        return Node(kind: nkImport, path: path)
    of tkPrint:
        p.next()
        return Node(kind: nkPrint, valNode: parseExpr(p))
    of tkExit:
        p.next()
        return Node(kind: nkExit, valNode: parseExpr(p))
    of tkJudge:
        p.next()
        let cond = parseExpr(p)
        p.expect tkColon
        let thenBody = parseBlock(p)
        var elseBody: Node = nil
        if p.peek.kind == tkSeal:
            p.next()
            if p.peek.kind == tkColon:
                p.next()
                elseBody = parseBlock(p)
            elif p.peek.kind == tkJudge:
                elseBody = parseStatement(p)
            else:
                raise newException(ValueError, "Expected ':' after seal")
        return Node(kind: nkJudge, condJudge: cond, thenBody: thenBody, elseBody: elseBody)
    of tkSpiral:
        p.next()
        let cond = parseExpr(p)
        p.expect tkColon
        let body = parseBlock(p)
        return Node(kind: nkSpiral, condJudge: cond, thenBody: body)
    of tkRite:
        p.next()
        if p.peek.kind != tkIdent: raise newException(ValueError, "Expected identifier after rite")
        let name = p.peek.name
        p.next()
        p.expect tkLPar
        var args: seq[string] = @[]
        while p.peek.kind == tkIdent:
            args.add(p.peek.name)
            p.next()
            if p.peek.kind == tkComma: p.next()
        p.expect tkRPar
        p.expect tkColon
        let body = parseBlock(p)
        return Node(kind: nkRite, funcName: name, args: args, body: body)
    of tkSeal:
        p.next()
        if p.peek.kind == tkColon:
            p.next()
            return parseBlock(p)
        elif p.peek.kind == tkIdent:
            let name = p.peek.name
            p.next()
            if p.peek.kind == tkAssign:
                p.next()
                let val = parseExpr(p)
                if isFloatNode(val, p):
                    p.floatVars.incl(name)
                if isStringNode(val, p):
                    p.stringVars.incl(name)
                return Node(kind: nkAssign, left: Node(kind: nkIdent, name: name), right: val)
            raise newException(ValueError, "Expected '=' after seal variable")
        raise newException(ValueError, "Expected identifier or ':' after seal")
    of tkVoid:
        p.next()
        p.expect tkColon
        let body = parseBlock(p)
        return Node(kind: nkVoid, children: body.children)
    of tkUsePython:
        p.next()
        p.expect tkLBrace
        let body = Node(kind: nkBlock, children: @[])
        while p.peek.kind != tkRBrace and p.peek.kind != tkEOF:
            let stmt = p.parseStatement()
            if stmt != nil: body.children.add(stmt)
        p.expect tkRBrace
        return Node(kind: nkUsePython, children: body.children)
    of tkRaw:
        p.next()
        let val = p.parseExpr()
        return Node(kind: nkRawExec, valNode: val)
    of tkPub:
        p.next()
        let stmt = p.parseStatement()
        if stmt != nil:
            stmt.kind = nkPub
        return stmt
    else:
        let leftNode = p.parseExpr()
        if p.peek.kind == tkAssign:
            if leftNode.kind == nkStructGet:
                p.next()
                let rightNode = p.parseExpr()
                return Node(kind: nkStructSet, structSetObj: leftNode.structGetObj,
                           structSetField: leftNode.structGetField, structSetVal: rightNode)
            if leftNode.kind != nkIdent and leftNode.kind != nkArrayGet:
                raise newException(ValueError, "Assignment target must be an identifier, field, or index")
            if leftNode.kind == nkArrayGet:
                p.next()
                let rightNode = p.parseExpr()
                return Node(kind: nkArraySet, arraySetArr: leftNode.arrayGetArr,
                           arraySetIdx: leftNode.arrayGetIdx, arraySetVal: rightNode)
            p.next()
            let rightNode = p.parseExpr()
            if isStringNode(rightNode, p):
                p.stringVars.incl(leftNode.name)
            return Node(kind: nkAssign, left: leftNode, right: rightNode)
        if p.peek.kind == tkDot:
            p.next()
            let field = expectFieldName(p)
            return Node(kind: nkStructGet, structGetObj: leftNode, structGetField: field)
        if p.peek.kind == tkLBkt:
            p.next()
            let idx = parseExpr(p)
            p.expect tkRBkt
            return Node(kind: nkArrayGet, arrayGetArr: leftNode, arrayGetIdx: idx)
        return leftNode

proc parseProgram*(p: var Parser): Node =
    result = Node(kind: nkProgram, children: @[])
    while p.peek.kind != tkEOF:
        let stmt = p.parseStatement()
        if stmt != nil:
            result.children.add(stmt)
        if p.peek.kind == tkSemicolon:
            p.next()
        elif stmt == nil and p.peek.kind notin {tkEOF, tkDedent}:
            p.next()
