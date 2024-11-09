import { ethers } from "hardhat";
import hre from "hardhat";
import utils from './$u'
import { commitmentAndNullifierHash } from "./VotersGenerator";
import * as snarkjs from "snarkjs";

const bmJSON = require("../../artifacts/contracts/ERC7208/BallotsManagerDataManager.sol/BallotsManagerDataManager.json");
const bmABI = bmJSON.abi;
const bmInterface = new hre.ethers.Interface(bmABI);

export async function getInputData(recipient: string , inputData: {secret: string, nullifier: string, txHash: string}){
    const receipt = await ethers.provider.getTransactionReceipt(inputData.txHash);
    const log = receipt!.logs[0];
    const decodedData = bmInterface.decodeEventLog("Voted", log.data, log.topics);
    let result = await commitmentAndNullifierHash(inputData.secret, inputData.nullifier)
    const proofInput = {
        "root": BigInt(decodedData.root).toString(),
        "nullifierHash": result[1].toString(),
        "recipient": utils.BNToDecimal(recipient),
        "secret": inputData.secret,
        "nullifier": inputData.nullifier,
        "pathElements": decodedData.hashPairings.map((n: string) => BigInt(n).toString()),
        "pathIndices": decodedData.hashDirections
    };
    const {proof, publicSignals} = await snarkjs.groth16.fullProve(proofInput, __dirname+"/withdraw_share.wasm", __dirname+"/setup_final.zkey")
    
    const callInputs = [
        proof.pi_a.slice(0, 2).map(utils.BN256ToHex),
        proof.pi_b.slice(0, 2).map((row) => (utils.reverseCoordinate(row.map(utils.BN256ToHex)))),
        proof.pi_c.slice(0, 2).map(utils.BN256ToHex),
        decodedData.root,
        utils.BN256ToHex(result[1].toString()),
        recipient
    ];
    return callInputs
}