// this code is based in https://github.com/darth-cy/NFTA-Tornado-Resources/blob/main/finale/frontend/utils/%24u.js
import { BigNumber } from "@ethersproject/bignumber";

const utils = {
    
    moveDecimalLeft: (str: string, count: number): string => {
        let start = str.length - count;
        let prePadding = "";

        while (start < 0) {
            prePadding += "0";
            start += 1;
        }

        str = prePadding + str;
        let result = str.slice(0, start) + "." + str.slice(start);
        if (result[0] === ".") {
            result = "0" + result;
        }

        return result;
    },

    BN256ToBin: (str: string): string => {
        let r = BigInt(str).toString(2);
        let prePadding = "";
        const paddingAmount = 256 - r.length;

        for (let i = 0; i < paddingAmount; i++) {
            prePadding += "0";
        }

        return prePadding + r;
    },

    BN256ToHex: (n: string | number | bigint): string => {
        let nstr = BigInt(n).toString(16);

        while (nstr.length < 64) {
            nstr = "0" + nstr;
        }

        return `0x${nstr}`;
    },

    BNToDecimal: (bn: string | number | BigNumber): string => {
        return BigNumber.from(bn).toString();
    },

    reverseCoordinate: (p: string[]): [string, string] => {
        return [p[1], p[0]];
    }
};

export default utils;
