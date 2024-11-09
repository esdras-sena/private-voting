import Web3Utils from "web3-utils";

class Contract {
    private code: number[] = [];
    private labels: Record<string, number> = {};
    private pendingLabels: Record<string, number[]> = {};

    createTxData(): string {
        let C: any;

        // Check all labels are defined
        const pendingLabels = Object.keys(this.pendingLabels);
        if (pendingLabels.length > 0) {
            throw new Error("Labels not defined: " + pendingLabels.join(", "));
        }

        let setLoaderLength = 0;
        let genLoadedLength = -1;

        while (genLoadedLength != setLoaderLength) {
            setLoaderLength = genLoadedLength;
            C = new Contract();
            C.codesize();
            C.push(setLoaderLength);
            C.push(0);
            C.codecopy();

            C.push(this.code.length);
            C.push(0);
            C.return();
            genLoadedLength = C.code.length;
        }

        return Web3Utils.bytesToHex(C.code.concat(this.code));
    }

    stop() { this.code.push(0x00); }
    add() { this.code.push(0x01); }
    mul() { this.code.push(0x02); }
    sub() { this.code.push(0x03); }
    div() { this.code.push(0x04); }
    sdiv() { this.code.push(0x05); }
    mod() { this.code.push(0x06); }
    smod() { this.code.push(0x07); }
    addmod() { this.code.push(0x08); }
    mulmod() { this.code.push(0x09); }
    exp() { this.code.push(0x0a); }
    signextend() { this.code.push(0x0b); }

    lt() { this.code.push(0x10); }
    gt() { this.code.push(0x11); }
    slt() { this.code.push(0x12); }
    sgt() { this.code.push(0x13); }
    eq() { this.code.push(0x14); }
    iszero() { this.code.push(0x15); }
    and() { this.code.push(0x16); }
    or() { this.code.push(0x17); }
    xor() { this.code.push(0x18); }
    not() { this.code.push(0x19); }
    byte() { this.code.push(0x1a); }

    keccak() { this.code.push(0x20); }
    sha3() { this.code.push(0x20); } // alias

    address() { this.code.push(0x30); }
    balance() { this.code.push(0x31); }
    origin() { this.code.push(0x32); }
    caller() { this.code.push(0x33); }
    callvalue() { this.code.push(0x34); }
    calldataload() { this.code.push(0x35); }
    calldatasize() { this.code.push(0x36); }
    calldatacopy() { this.code.push(0x37); }
    codesize() { this.code.push(0x38); }
    codecopy() { this.code.push(0x39); }
    gasprice() { this.code.push(0x3a); }
    extcodesize() { this.code.push(0x3b); }
    extcodecopy() { this.code.push(0x3c); }
    returndatasize() { this.code.push(0x3d); }
    returndatacopy() { this.code.push(0x3e); }

    blockhash() { this.code.push(0x40); }
    coinbase() { this.code.push(0x41); }
    timestamp() { this.code.push(0x42); }
    number() { this.code.push(0x43); }
    difficulty() { this.code.push(0x44); }
    gaslimit() { this.code.push(0x45); }

    pop() { this.code.push(0x50); }
    mload() { this.code.push(0x51); }
    mstore() { this.code.push(0x52); }
    mstore8() { this.code.push(0x53); }
    sload() { this.code.push(0x54); }
    sstore() { this.code.push(0x55); }

    private _pushLabel(label: string) {
        if (this.labels[label] !== undefined) {
            this.push(this.labels[label]);
        } else {
            this.pendingLabels[label] = this.pendingLabels[label] || [];
            this.pendingLabels[label].push(this.code.length);
            this.push("0x000000");
        }
    }

    private _fillLabel(label: string) {
        if (!this.pendingLabels[label]) return;

        const dst = this.labels[label];
        const dst3 = [dst >> 16, (dst >> 8) & 0xFF, dst & 0xFF];

        this.pendingLabels[label].forEach((p) => {
            for (let i = 0; i < 3; i++) {
                this.code[p + i + 1] = dst3[i];
            }
        });

        delete this.pendingLabels[label];
    }

    jmp(label?: string) {
        if (label !== undefined) {
            this._pushLabel(label);
        }
        this.code.push(0x56);
    }

    jmpi(label?: string) {
        if (label !== undefined) {
            this._pushLabel(label);
        }
        this.code.push(0x57);
    }

    pc() { this.code.push(0x58); }
    msize() { this.code.push(0x59); }
    gas() { this.code.push(0x5a); }

    label(name: string) {
        if (this.labels[name] !== undefined) {
            throw new Error("Label already defined");
        }
        this.labels[name] = this.code.length;
        this.code.push(0x5b);
        this._fillLabel(name);
    }

    push(data: string | number) {
        const d = Web3Utils.hexToBytes(Web3Utils.toHex(data));
        if (d.length === 0 || d.length > 32) {
            throw new Error("Data length must be between 1 and 32 bytes");
        }
        this.code = this.code.concat([0x5F + d.length], d);
    }

    dup(n: number) {
        if (n < 0 || n >= 16) {
            throw new Error("Duplication number must be between 0 and 15");
        }
        this.code.push(0x80 + n);
    }

    swap(n: number) {
        if (n < 1 || n > 16) {
            throw new Error("Swap number must be between 1 and 16");
        }
        this.code.push(0x8f + n);
    }

    log0() { this.code.push(0xa0); }
    log1() { this.code.push(0xa1); }
    log2() { this.code.push(0xa2); }
    log3() { this.code.push(0xa3); }
    log4() { this.code.push(0xa4); }

    create() { this.code.push(0xf0); }
    call() { this.code.push(0xf1); }
    callcode() { this.code.push(0xf2); }
    return() { this.code.push(0xf3); }
    delegatecall() { this.code.push(0xf4); }
    staticcall() { this.code.push(0xfa); }
    revert() { this.code.push(0xfd); }
    invalid() { this.code.push(0xfe); }
    selfdestruct() { this.code.push(0xff); }
}

export default Contract;
