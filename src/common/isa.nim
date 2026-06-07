# src/common/isa.nim
import tables

type
    OpCode* = enum
        opPush = 0x01.uint8
        opAdd = 0x02.uint8
        opSub = 0x03.uint8
        opMul = 0x04.uint8
        opDiv = 0x05.uint8
        opXor = 0x06.uint8
        opAnd = 0x07.uint8
        opOr = 0x08.uint8
        opShl = 0x09.uint8
        opShr = 0x0A.uint8
        opStore = 0x10.uint8
        opLoad = 0x11.uint8
        opDup = 0x12.uint8
        opPop = 0x13.uint8
        opPrint = 0x20.uint8
        opEq = 0x30.uint8
        opNe = 0x31.uint8
        opLt = 0x32.uint8
        opGt = 0x33.uint8
        opLe = 0x34.uint8
        opGe = 0x35.uint8
        opJmp = 0x40.uint8
        opJz = 0x41.uint8
        opCall = 0x42.uint8
        opRet = 0x43.uint8
        opOpen = 0x50.uint8
        opClose = 0x51.uint8
        opRead = 0x52.uint8
        opWrite = 0x53.uint8
        opCopyAll = 0x54.uint8
        opExit = 0xFF.uint8
        opNoise = 0xEE.uint8
        opCheck = 0xFB.uint8
        opEncrypt = 0x60.uint8
        opWriteBlock = 0x61.uint8
        opEvolve = 0x62.uint8
        opHistoryHash = 0x63.uint8
        opInitEngine = 0x64.uint8
        opGetArg = 0x65.uint8
        opCompile = 0x66.uint8
        # V9: Integration ISA
        opMapNew = 0x70.uint8
        opMapSet = 0x71.uint8
        opMapGet = 0x72.uint8
        opListAppend = 0x73.uint8
        opPushStr = 0x90.uint8
        opInput = 0x91.uint8
        # V10: Asset Assimilation & Space Isolation
        opLoadAtb = 0xA0.uint8
        opSwitchParser = 0xA1.uint8
        opRawExec = 0xA2.uint8
        opAbsolution = 0xB0.uint8
        # V11: Float / Int64 / List Index
        opPushFlt = 0x14.uint8
        opPush64  = 0x15.uint8
        opFAdd = 0x16.uint8
        opFSub = 0x17.uint8
        opFMul = 0x18.uint8
        opFDiv = 0x19.uint8
        opAdd64 = 0x1A.uint8
        opSub64 = 0x1B.uint8
        opMul64 = 0x1C.uint8
        opDiv64 = 0x1D.uint8
        opListGet = 0x1E.uint8
        opStrCat = 0x1F.uint8

    FheBlock* = object
        low*: uint64
        high*: uint64

    # 動的ISAマップ : ビルド時にシャッフルされる対応表
    ISAMap* = Table[uint8, OpCode]

const CREATOR_PUB_KEY* = "ATOMEIS_CREATOR_V8_9999" # Placeholder for actual public key