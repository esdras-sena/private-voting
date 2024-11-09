import utils from "./$u";
import path from 'path';
import fs from 'fs';
const builder = require('../../circuit/vote_js/witness_calculator');

import { ethers } from "hardhat";

export type Voter = {secret: string, nullifier: string, account: any}


export function generateVoters(numberOfVoters: number): Voter[] {
    let voters: Voter[] = []
    for(let i = 0; i < numberOfVoters;i++){
        let [s, n] = generateSecretAndNullifier()
        let acc = new ethers.Wallet(secret2privKey(s),ethers.provider)
        voters[i] = {secret: s, nullifier: n, account: acc}
    } 
    return voters
}

export function secret2privKey(secret: string): string {
    const hashedString = ethers.keccak256(ethers.toUtf8Bytes(secret));

    const privateKey = hashedString.slice(2);

    if (privateKey.length !== 64) {
        throw new Error("Invalid private key length generated.");
    }

    return "0x" + privateKey;
}

export function generateSecretAndNullifier(): [string, string] {
    const secret = uint8ArrayTo256BitBigInt(ethers.randomBytes(32)).toString();
    const nullifier = uint8ArrayTo256BitBigInt(ethers.randomBytes(32)).toString();
    return [secret, nullifier]
}

export async function commitmentAndNullifierHash(secret: string, nullifier: string): Promise<bigint[]> {
    const wasmPath = path.join(__dirname,'vote.wasm');
    const buffer = fs.readFileSync(wasmPath);
    const depositWC = await builder(new Uint8Array(buffer));
    let input = {
        secret: secret,
        nullifier: nullifier
    }

    const r = await depositWC.calculateWitness(input, 0);
    const commitment = r[1];
    const nullifierHash = r[2];
    return [commitment, nullifierHash]
}

function uint8ArrayTo256BitBigInt(uint8Array: Uint8Array): bigint {
    if (uint8Array.length !== 32) {
      throw new Error("Uint8Array must be exactly 32 bytes for a 256-bit integer.");
    }
  
    let result = BigInt(0);
    for (const byte of uint8Array) {
      result = (result << BigInt(8)) + BigInt(byte);
    }
  
    return result;
}