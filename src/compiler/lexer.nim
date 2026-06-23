import parseutils, types

proc tokenize*(input: string): seq[Token] =
    var i = 0
    var indentStack = @[0]
    var atLineStart = true

    while i < input.len:
        if atLineStart:
            var indent = 0
            while i < input.len and (input[i] == ' ' or input[i] == '\t'):
                if input[i] == ' ': inc indent
                else: indent += 4
                inc i

            if i >= input.len: break
            if input[i] in {'\r', '\n', '#'}:
                if input[i] == '#':
                    while i < input.len and input[i] != '\n': inc i
                if i < input.len and input[i] == '\r': inc i
                if i < input.len and input[i] == '\n': inc i
                atLineStart = true
                continue

            if indent > indentStack[^1]:
                indentStack.add(indent)
                result.add Token(kind: tkIndent)
            elif indent < indentStack[^1]:
                while indent < indentStack[^1]:
                    discard indentStack.pop()
                    result.add Token(kind: tkDedent)
                if indent != indentStack[^1]:
                    raise newException(ValueError, "Indentation error")
            atLineStart = false

        if i >= input.len: break

        case input[i]
        of ' ', '\t', '\r': inc i
        of '\n':
            inc i
            atLineStart = true
        of '+': (result.add Token(kind: tkPlus); inc i)
        of '-':
            if i + 1 < input.len and input[i+1] == '>':
                result.add Token(kind: tkArrow)
                i += 2
            else:
                result.add Token(kind: tkMinus)
                inc i
        of '*': (result.add Token(kind: tkMul); inc i)
        of '/': (result.add Token(kind: tkDiv); inc i)
        of '%': (result.add Token(kind: tkMod); inc i)
        of '\'':
            inc i
            if i < input.len:
                var ch: int
                if input[i] == '\\' and i + 1 < input.len:
                    inc i
                    case input[i]
                    of 'n': ch = 10
                    of 't': ch = 9
                    of 'r': ch = 13
                    of '\\': ch = 92
                    of '\'': ch = 39
                    else: ch = input[i].ord
                    inc i
                else:
                    ch = input[i].ord
                    inc i
                if i < input.len and input[i] == '\'': inc i
                result.add Token(kind: tkInt, val: ch)
            else:
                raise newException(ValueError, "Unterminated char literal")
        of '(': (result.add Token(kind: tkLPar); inc i)
        of ')': (result.add Token(kind: tkRPar); inc i)
        of '[': (result.add Token(kind: tkLBkt); inc i)
        of ']': (result.add Token(kind: tkRBkt); inc i)
        of '.':
            if i + 1 < input.len and input[i+1] == '.':
                result.add Token(kind: tkDot); inc i; inc i
            else:
                result.add Token(kind: tkDot); inc i
        of '=':
            if i + 1 < input.len and input[i+1] == '=':
                result.add Token(kind: tkEq)
                i += 2
            else:
                result.add Token(kind: tkAssign)
                inc i
        of '!':
            if i + 1 < input.len and input[i+1] == '=':
                result.add Token(kind: tkNe)
                i += 2
            else:
                result.add Token(kind: tkNot)
                inc i
        of '<':
            if i + 1 < input.len and input[i+1] == '<':
                result.add Token(kind: tkShl)
                i += 2
            elif i + 1 < input.len and input[i+1] == '=':
                result.add Token(kind: tkLe)
                i += 2
            else:
                result.add Token(kind: tkLt)
                inc i
        of '>':
            if i + 1 < input.len and input[i+1] == '>':
                result.add Token(kind: tkShr)
                i += 2
            elif i + 1 < input.len and input[i+1] == '=':
                result.add Token(kind: tkGe)
                i += 2
            else:
                result.add Token(kind: tkGt)
                inc i
        of '^': (result.add Token(kind: tkXor); inc i)
        of ':': (result.add Token(kind: tkColon); inc i)
        of ',': (result.add Token(kind: tkComma); inc i)
        of ';': (result.add Token(kind: tkSemicolon); inc i)
        of '{': (result.add Token(kind: tkLBrace); inc i)
        of '}': (result.add Token(kind: tkRBrace); inc i)
        of '"':
            inc i
            var s = ""
            while i < input.len and input[i] != '"':
                if input[i] == '\\' and i + 1 < input.len:
                    inc i
                    case input[i]
                    of 'n': s.add('\n')
                    of 't': s.add('\t')
                    of 'r': s.add('\r')
                    of '\\': s.add('\\')
                    of '"': s.add('"')
                    else: s.add(input[i])
                else:
                    s.add(input[i])
                inc i
            if i < input.len: inc i
            result.add Token(kind: tkString, strVal: s)
        of '0'..'9':
            var val: int
            let length = parseInt(input, val, i)
            var j = i + length
            if j < input.len and input[j] == '.' and j + 1 < input.len and input[j+1] in {'0'..'9'}:
                var floatStr = ""
                var k = i
                while k < input.len and input[k] in {'0'..'9', '.'}:
                    floatStr.add(input[k]); inc k
                var fval: float
                try:
                    discard parseFloat(floatStr, fval)
                except:
                    fval = 0.0
                result.add Token(kind: tkFloat, floatVal: fval.float32)
                i = k
            elif j < input.len and (input[j] in {'l', 'L'} or (j + 1 < input.len and input[j] == '6' and input[j+1] == '4')):
                if input[j] == '6':
                    result.add Token(kind: tkInt64, val64: val.int64)
                    i += length + 3
                else:
                    result.add Token(kind: tkInt64, val64: val.int64)
                    i += length + 1
            else:
                result.add Token(kind: tkInt, val: val)
                i += length
        of 'a'..'z', 'A'..'Z', '_':
            var s = ""
            while i < input.len and input[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
                s.add(input[i]); inc i

            case s
            of "import": result.add Token(kind: tkImport)
            of "reveal": result.add Token(kind: tkPrint)
            of "exit": result.add Token(kind: tkExit)
            of "judge": result.add Token(kind: tkJudge)
            of "seal": result.add Token(kind: tkSeal)
            of "spiral": result.add Token(kind: tkSpiral)
            of "rite": result.add Token(kind: tkRite)
            of "jmp": result.add Token(kind: tkJmp)
            of "jz": result.add Token(kind: tkJz)
            of "void": result.add Token(kind: tkVoid)
            of "use_python": result.add Token(kind: tkUsePython)
            of "raw": result.add Token(kind: tkRaw)
            of "getarg": result.add Token(kind: tkGetArg)
            of "open": result.add Token(kind: tkOpen)
            of "read": result.add Token(kind: tkRead)
            of "close": result.add Token(kind: tkClose)
            of "write": result.add Token(kind: tkWrite)
            of "stigma": result.add Token(kind: tkStigma)
            of "fate": result.add Token(kind: tkFate)
            of "abyss": result.add Token(kind: tkAbyss)
            of "orbit": result.add Token(kind: tkOrbit)
            of "bool": result.add Token(kind: tkBool)
            of "true": result.add Token(kind: tkTrue)
            of "false": result.add Token(kind: tkFalse)
            of "if": result.add Token(kind: tkIf)
            of "elif": result.add Token(kind: tkElif)
            of "else": result.add Token(kind: tkElse)
            of "while": result.add Token(kind: tkWhile)
            of "for": result.add Token(kind: tkFor)
            of "in": result.add Token(kind: tkIn)
            of "break": result.add Token(kind: tkBreak)
            of "continue": result.add Token(kind: tkContinue)
            of "return": result.add Token(kind: tkReturn)
            of "struct": result.add Token(kind: tkStruct)
            of "fn": result.add Token(kind: tkFn)
            of "let": result.add Token(kind: tkLet)
            of "var": result.add Token(kind: tkVar)
            of "nil": result.add Token(kind: tkNil)
            of "as": result.add Token(kind: tkAs)
            of "not": result.add Token(kind: tkNot)
            of "sizeof": result.add Token(kind: tkSizeof)
            of "alloc": result.add Token(kind: tkAlloc)
            of "free": result.add Token(kind: tkFree)
            of "extern": result.add Token(kind: tkExtern)
            of "ptr": result.add Token(kind: tkPtr)
            of "addr": result.add Token(kind: tkAddr)
            of "module": result.add Token(kind: tkModule)
            of "pub": result.add Token(kind: tkPub)
            of "enum": result.add Token(kind: tkEnum)
            of "type": result.add Token(kind: tkType)
            else: result.add Token(kind: tkIdent, name: s)
        else:
            if input[i] == '#':
                while i < input.len and input[i] != '\n': inc i
                atLineStart = true
            else:
                raise newException(ValueError, "Unknown char: " & input[i])

    while indentStack.len > 1:
        discard indentStack.pop()
        result.add Token(kind: tkDedent)

    result.add Token(kind: tkEOF)
