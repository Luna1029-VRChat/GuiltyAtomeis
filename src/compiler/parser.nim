# src/compiler/parser.nim
import types, sets

type Parser* = object
    tokens*: seq[Token]
    pos*: int
    floatVars*: HashSet[string]
    stringVars*: HashSet[string]

proc peek(p: Parser): Token = 
    if p.pos >= p.tokens.len: return Token(kind: tkEOF)
    return p.tokens[p.pos]
proc next(p: var Parser) = 
    inc p.pos

proc parseExpr(p: var Parser): Node # Forward declaration

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
    of tkIdent:
        p.next()
        # V9 Built-in Functions
        if t.name == "confess" or t.name == "input":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after " & t.name)
            p.next()
            if p.peek.kind != tkRPar: discard parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkInput)
        elif t.name == "map_new":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after map_new")
            p.next()
            var size: Node = nil
            if p.peek.kind != tkRPar: size = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkMapNew, valNode: size)
        elif t.name == "map_set":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after map_set")
            p.next(); let mid = parseExpr(p)
            if p.peek.kind != tkComma: raise newException(ValueError, "Expected ','")
            p.next(); let key = parseExpr(p)
            if p.peek.kind != tkComma: raise newException(ValueError, "Expected ','")
            p.next(); let val = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkMapSet, mapId: mid, keyNode: key, valNodeSet: val)
        elif t.name == "map_get":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after map_get")
            p.next(); let mid = parseExpr(p)
            if p.peek.kind != tkComma: raise newException(ValueError, "Expected ','")
            p.next(); let key = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkMapGet, mapIdGet: mid, keyNodeGet: key)
        elif t.name == "copy_all":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after copy_all")
            p.next()
            let src = parseExpr(p)
            if p.peek.kind != tkComma: raise newException(ValueError, "Expected ',' after copy_all src")
            p.next()
            let dst = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')' after copy_all args")
            p.next()
            return Node(kind: nkCopyAll, copySrc: src, copyDst: dst)
        elif t.name == "check":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after check")
            p.next()
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkCheck, valNode: nil)
        elif t.name == "encrypt":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after encrypt")
            p.next()
            let val = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkEncrypt, valNode: val)
        elif t.name == "evolve":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after evolve")
            p.next()
            let val = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkEvolve, valNode: val)
        elif t.name == "history_hash":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after history_hash")
            p.next()
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkHistoryHash, valNode: nil)
        elif t.name == "init_engine":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after init_engine")
            p.next()
            let val = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkInitEngine, valNode: val)
        elif t.name == "compile":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after compile")
            p.next()
            let val = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next()
            return Node(kind: nkCompile, valNode: val)
        elif t.name == "list_append":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after list_append")
            p.next()
            let lid = parseExpr(p)
            if p.peek.kind != tkComma: raise newException(ValueError, "Expected ',' after list_append listId")
            p.next()
            let lval = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')' after list_append args")
            p.next()
            return Node(kind: nkListAppend, listAppendListId: lid, listAppendVal: lval)
        elif t.name == "write_block":
            if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after write_block")
            p.next()
            let fid = parseExpr(p)
            if p.peek.kind != tkComma: raise newException(ValueError, "Expected ',' after write_block fid")
            p.next()
            let wval = parseExpr(p)
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')' after write_block args")
            p.next()
            return Node(kind: nkWriteBlock, writeFid: fid, writeVal: wval)
        elif p.peek.kind == tkLPar: # User function call
            p.next() # (
            var args: seq[Node] = @[]
            while p.peek.kind != tkRPar and p.peek.kind != tkEOF:
                args.add(p.parseExpr())
                if p.peek.kind == tkComma: p.next()
            if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
            p.next() # )
            return Node(kind: nkCall, callName: t.name, callArgs: args)
        # リスト/マップインデックス ident[expr]
        if p.peek.kind == tkLBkt:
            p.next()
            let idx = p.parseExpr()
            if p.peek.kind != tkRBkt: raise newException(ValueError, "Expected ']'")
            p.next()
            return Node(kind: nkListGet, listGetListId: Node(kind: nkIdent, name: t.name), listGetIndex: idx)
        return Node(kind: nkIdent, name: t.name)
    of tkGetArg, tkOpen, tkRead, tkClose, tkRaw:
        let tkind = t.kind
        p.next()
        if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after " & $tkind)
        p.next()
        var val: Node = nil
        if p.peek.kind != tkRPar: val = parseExpr(p)
        if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')'")
        p.next()
        case tkind:
            of tkGetArg: return Node(kind: nkGetArg, valNode: val)
            of tkOpen: return Node(kind: nkOpen, valNode: val)
            of tkRead: return Node(kind: nkRead, valNode: val)
            of tkClose: return Node(kind: nkClose, valNode: val)
            of tkRaw: return Node(kind: nkRawExec, valNode: val)
            else: return Node(kind: nkRawExec, valNode: val)
    of tkWrite:
        p.next()
        if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after write")
        p.next()
        let fid = parseExpr(p)
        if p.peek.kind != tkComma: raise newException(ValueError, "Expected ',' after fid in write()")
        p.next()
        let wval = parseExpr(p)
        if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')' after write args")
        p.next()
        return Node(kind: nkWrite, writeFid: fid, writeVal: wval)
    of tkLPar:
        p.next()
        result = parseExpr(p)
        if p.peek.kind != tkRPar:
            raise newException(ValueError, "Expected ')'")
        p.next()
    else:
        raise newException(ValueError, "Expected expression but got " & $t.kind & " at pos " & $p.pos)

proc isFloatNode(n: Node, p: Parser): bool =
    result = n.kind in {nkFloat, nkFAdd, nkFSub, nkFMul, nkFDiv}
    if not result and n.kind == nkIdent:
        result = n.name in p.floatVars

proc isStringNode(n: Node, p: Parser): bool =
    result = n.kind in {nkString, nkStrCat}
    if not result and n.kind == nkIdent:
        result = n.name in p.stringVars

proc parseTerm(p: var Parser): Node =
    result = parseFactor(p)
    while p.peek.kind in {tkMul, tkDiv}:
        let op = p.peek.kind
        p.next()
        let right = parseFactor(p)
        if isFloatNode(result, p) or isFloatNode(right, p):
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

proc parseExpr(p: var Parser): Node =
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

proc parseStatement*(p: var Parser): Node # Forward declaration

proc parseBlock(p: var Parser): Node =
    if p.peek.kind != tkIndent:
        # Single statement block (possibly multiple on same line separated by ;)
        result = Node(kind: nkBlock, children: @[])
        while true:
            let stmt = p.parseStatement()
            if stmt != nil:
                result.children.add(stmt)
            if p.peek.kind == tkSemicolon:
                p.next() # skip ;
            else:
                break
        return result
    
    p.next() # tkIndent
    result = Node(kind: nkBlock, children: @[])
    while p.peek.kind != tkDedent and p.peek.kind != tkEOF:
        let stmt = p.parseStatement()
        if stmt != nil:
            result.children.add(stmt)
        if p.peek.kind == tkSemicolon:
            p.next() # skip ; between statements
    if p.peek.kind == tkDedent: p.next()

proc parseStigma(p: var Parser): Node =
    p.next() # tkStigma
    let expr = parseExpr(p)
    if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after stigma expr")
    p.next()
    if p.peek.kind != tkIndent: raise newException(ValueError, "Expected indent after stigma:")
    p.next()
    
    result = Node(kind: nkStigma, children: @[expr])
    
    while p.peek.kind in {tkFate, tkAbyss}:
        let tkind = p.peek.kind
        p.next()
        var val: Node = nil
        if tkind == tkFate:
            val = parseExpr(p)
        if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after fate/abyss")
        p.next()
        let body = parseBlock(p)
        result.children.add(Node(kind: nkFate, fateVal: val, fateBody: body))
        
    if p.peek.kind == tkDedent: p.next()

proc parseOrbit(p: var Parser): Node =
    p.next() # tkOrbit
    if p.peek.kind != tkIdent: raise newException(ValueError, "Expected identifier after orbit")
    let varName = p.peek.name
    p.next()
    if p.peek.kind != tkIdent or p.peek.name != "in":
        raise newException(ValueError, "Expected 'in' after orbit variable")
    p.next()
    let count = parseExpr(p)
    if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after orbit count")
    p.next()
    let body = parseBlock(p)
    return Node(kind: nkOrbit, loopVar: varName, loopCount: count, loopBody: body)

proc parseStatement*(p: var Parser): Node =
    let t = p.peek
    case t.kind
    of tkEOF: return nil
    of tkStigma: return parseStigma(p)
    of tkOrbit: return parseOrbit(p)
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
        if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after judge condition")
        p.next()
        let thenBody = parseBlock(p)
        var elseBody: Node = nil
        if p.peek.kind == tkSeal:
            p.next()
            if p.peek.kind == tkColon:
                p.next()
                elseBody = parseBlock(p)
            elif p.peek.kind == tkJudge: # elif using judge
                elseBody = parseStatement(p)
            else:
                raise newException(ValueError, "Expected ':' after seal")
        return Node(kind: nkJudge, condJudge: cond, thenBody: thenBody, elseBody: elseBody)
    of tkSpiral:
        p.next()
        let cond = parseExpr(p)
        if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after spiral condition")
        p.next()
        let body = parseBlock(p)
        return Node(kind: nkSpiral, condJudge: cond, thenBody: body)
    of tkRite:
        p.next()
        if p.peek.kind != tkIdent: raise newException(ValueError, "Expected identifier after rite")
        let name = p.peek.name
        p.next()
        if p.peek.kind != tkLPar: raise newException(ValueError, "Expected '(' after function name")
        p.next()
        var args: seq[string] = @[]
        while p.peek.kind == tkIdent:
            args.add(p.peek.name)
            p.next()
            if p.peek.kind == tkComma: p.next()
        if p.peek.kind != tkRPar: raise newException(ValueError, "Expected ')' after args")
        p.next()
        if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after rite")
        p.next()
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
        if p.peek.kind != tkColon: raise newException(ValueError, "Expected ':' after void")
        p.next()
        let body = parseBlock(p)
        return Node(kind: nkVoid, children: body.children)
    of tkUsePython:
        p.next()
        if p.peek.kind != tkLBrace: raise newException(ValueError, "Expected '{' after use_python")
        p.next()
        # For now, just capture statements inside or treat as a block
        let body = Node(kind: nkBlock, children: @[])
        while p.peek.kind != tkRBrace and p.peek.kind != tkEOF:
            let stmt = p.parseStatement()
            if stmt != nil: body.children.add(stmt)
        if p.peek.kind != tkRBrace: raise newException(ValueError, "Expected '}' after use_python block")
        p.next()
        return Node(kind: nkUsePython, children: body.children)
    of tkRaw:
        p.next()
        let val = p.parseExpr()
        return Node(kind: nkRawExec, valNode: val)
    else:
        let leftNode = p.parseExpr()
        if p.peek.kind == tkAssign:
            if leftNode.kind != nkIdent:
                raise newException(ValueError, "Assignment target must be an identifier")
            p.next()
            let rightNode = p.parseExpr()
            if isStringNode(rightNode, p):
                p.stringVars.incl(leftNode.name)
            return Node(kind: nkAssign, left: leftNode, right: rightNode)
        return leftNode

proc parseProgram*(p: var Parser): Node =
    result = Node(kind: nkProgram, children: @[])
    while p.peek.kind != tkEOF:
        let stmt = p.parseStatement()
        if stmt != nil:
            result.children.add(stmt)
        if p.peek.kind == tkSemicolon:
            p.next() # skip ; between top-level statements
        elif stmt == nil and p.peek.kind notin {tkEOF, tkDedent}:
            p.next() # Skip unexpected tokens like Dedent if top level
