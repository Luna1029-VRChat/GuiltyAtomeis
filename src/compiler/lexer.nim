# src/compiler/lexer.nim
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
                else: indent += 4 # tab = 4 spaces
                inc i
            
            # Check for empty lines or comments
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
            # result.add Token(kind: tkNewline) # Optional, depends on parser
            inc i
            atLineStart = true
        of '+': (result.add Token(kind: tkPlus); inc i)
        of '-': (result.add Token(kind: tkMinus); inc i)
        of '*': (result.add Token(kind: tkMul); inc i)
        of '/': (result.add Token(kind: tkDiv); inc i)
        of '(': (result.add Token(kind: tkLPar); inc i)
        of ')': (result.add Token(kind: tkRPar); inc i)
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
                raise newException(ValueError, "Unknown char: !")
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
        of '[': (result.add Token(kind: tkLBkt); inc i)
        of ']': (result.add Token(kind: tkRBkt); inc i)
        of ';': (result.add Token(kind: tkSemicolon); inc i)
        of '{': (result.add Token(kind: tkLBrace); inc i)
        of '}': (result.add Token(kind: tkRBrace); inc i)
        of '"': # V9: String literal
            inc i
            var s = ""
            while i < input.len and input[i] != '"':
                s.add(input[i]); inc i
            if i < input.len: inc i # skip "
            result.add Token(kind: tkString, strVal: s)
        of '0'..'9':
            var val: int
            let length = parseInt(input, val, i)
            var j = i + length
            # Check for float (digit.digit)
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
            else: result.add Token(kind: tkIdent, name: s)
        else:
            if input[i] == '#':
                while i < input.len and input[i] != '\n': inc i
                atLineStart = true
            else:
                raise newException(ValueError, "Unknown char: " & input[i])
    
    # Close any remaining indents
    while indentStack.len > 1:
        discard indentStack.pop()
        result.add Token(kind: tkDedent)
        
    result.add Token(kind: tkEOF)
