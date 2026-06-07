# src/common/compression.nim
import tables, algorithm

type
    HuffNode = ref object
        ch: uint8
        freq: int
        left, right: HuffNode

proc newNode(ch: uint8, freq: int): HuffNode =
    HuffNode(ch: ch, freq: freq, left: nil, right: nil)

proc buildHuffmanTree(data: seq[uint8]): HuffNode =
    var freqMap = initCountTable[uint8]()
    for b in data: freqMap.inc(b)
    
    var nodes: seq[HuffNode] = @[]
    for ch, freq in freqMap:
        nodes.add(newNode(ch, freq))
    
    while nodes.len > 1:
        nodes.sort(proc (a, b: HuffNode): int = a.freq - b.freq)
        let left = nodes[0]
        let right = nodes[1]
        let parent = newNode(0, left.freq + right.freq)
        parent.left = left
        parent.right = right
        nodes.del(1)
        nodes.del(0)
        nodes.add(parent)
    
    return if nodes.len > 0: nodes[0] else: nil

proc buildMap(node: HuffNode, prefix: string, huffMap: var Table[uint8, string]) =
    if node == nil: return
    if node.left == nil and node.right == nil:
        huffMap[node.ch] = if prefix == "": "0" else: prefix
        return
    buildMap(node.left, prefix & "0", huffMap)
    buildMap(node.right, prefix & "1", huffMap)

proc compress*(data: seq[uint8]): (string, Table[uint8, string]) =
    if data.len == 0: return ("", initTable[uint8, string]())
    let tree = buildHuffmanTree(data)
    var huffMap = initTable[uint8, string]()
    buildMap(tree, "", huffMap)
    
    var bitStr = ""
    for b in data:
        bitStr &= huffMap[b]
    
    return (bitStr, huffMap)

proc decompress*(bitStr: string, huffMap: Table[uint8, string], originalLen: int): seq[uint8] =
    if bitStr == "" or huffMap.len == 0: return @[]
    
    var reverseMap = initTable[string, uint8]()
    for k, v in huffMap: reverseMap[v] = k
    
    result = @[]
    var current = ""
    for bit in bitStr:
        current &= bit
        if reverseMap.hasKey(current):
            result.add(reverseMap[current])
            current = ""
            if result.len == originalLen: break
