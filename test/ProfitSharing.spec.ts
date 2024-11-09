import { expect } from "chai";
import hre from "hardhat";
import { bigIntToBytes, encodeDP, setupERC7208 } from "./helper/setupERC7208";
import { Voter, commitmentAndNullifierHash, generateVoters } from "./helper/VotersGenerator";
import { getInputData } from "./helper/withdrawUtils";
import { ProfitSharingDataManager } from "../typechain-types";

//  THIS TEST NEEDS TO BE REFACTORED
describe("Profit sharing test", async () => {
    let profitSharingDM: ProfitSharingDataManager;
    let callInputs1: any[];
    let callInputs2: any[];
    let callInputs3: any[];
    let voters: Voter[];
    let cnh2: bigint[];
    let cnh3: bigint[];

    beforeEach(async () => {
        const [owner, impostor, acc1, acc2, acc3] = await hre.ethers.getSigners()
        const [dataIndex, dataPointRegistry] = await setupERC7208()
        await dataPointRegistry.allocate(owner.address)
        const diAddr = await dataIndex.getAddress()
        const dprAddr = await dataPointRegistry.getAddress()

        const soulBoundedTokenDO = await hre.ethers.deployContract("SoulBoundedTokenDO")
        const sbtDOAddr = await soulBoundedTokenDO.getAddress()
        const cannesSBTDataManager = await hre.ethers.deployContract("CannesSBTDataManager", [owner.address, 'CannesID', diAddr, sbtDOAddr, encodeDP(dprAddr, 1)])
        const csDM = await cannesSBTDataManager.getAddress()

        const verifier = await hre.ethers.deployContract("Groth16Verifier")
        const verifierAddr = await verifier.getAddress()


        const hJSON = require('./helper/Hasher.json')
        const factory = new hre.ethers.ContractFactory(hJSON.abi, hJSON.bytecode, owner);
        let hasher = await factory.deploy()
        const hasherAddr = await hasher.getAddress()

        const ballotsManagerDO = await hre.ethers.deployContract("BallotsManagerDO")
        const bmDO = await ballotsManagerDO.getAddress()
        const ballotsManagerDataManager = await hre.ethers.deployContract("BallotsManagerDataManager", [diAddr, bmDO, hasherAddr, encodeDP(dprAddr, 1), csDM])
        const ballotsManagerAddr = ballotsManagerDataManager.getAddress()

        const profitSharingDO = await hre.ethers.deployContract("ProfitSharingDO")
        const psDO = await profitSharingDO.getAddress()
        profitSharingDM = await hre.ethers.deployContract("ProfitSharingDataManager", [diAddr, psDO, encodeDP(dprAddr, 1), ballotsManagerAddr])
        const psAddr = await profitSharingDM.getAddress()


        await profitSharingDO.setDIImplementation(encodeDP(dprAddr, 1), diAddr)
        await soulBoundedTokenDO.setDIImplementation(encodeDP(dprAddr, 1), diAddr)
        await ballotsManagerDO.setDIImplementation(encodeDP(dprAddr, 1), diAddr)
        await dataIndex.allowDataManager(encodeDP(dprAddr, 1), ballotsManagerAddr, true)
        await dataIndex.allowDataManager(encodeDP(dprAddr, 1), csDM, true)
        await dataIndex.allowDataManager(encodeDP(dprAddr, 1), psAddr, true)

        await profitSharingDM.setVerifier(verifierAddr)
        voters = generateVoters(6)

        await ballotsManagerDataManager.addProposal("Interstellar")
        await ballotsManagerDataManager.addProposal("Inception")

        for (let i = 0; i < 3; i++) {
            await cannesSBTDataManager.issue(voters[i].account.address, `ipfs://Voter${i}`);
            await owner.sendTransaction({
                to: voters[i].account.address,
                value: hre.ethers.parseEther("1.0"), // Sends exactly 1.0 ether
            });
        }

        let cnh1 = await commitmentAndNullifierHash(voters[0].secret, voters[0].nullifier)
        let tx = await ballotsManagerDataManager.connect(voters[0].account).vote(bigIntToBytes(cnh1[0]), 0)
        callInputs1 = await getInputData(acc1.address, { secret: voters[0].secret, nullifier: voters[0].nullifier, txHash: tx.hash })
        cnh2 = await commitmentAndNullifierHash(voters[1].secret, voters[1].nullifier)
        tx = await ballotsManagerDataManager.connect(voters[1].account).vote(bigIntToBytes(cnh2[0]), 1)
        callInputs2 = await getInputData(acc1.address, { secret: voters[1].secret, nullifier: voters[1].nullifier, txHash: tx.hash })
        cnh3 = await commitmentAndNullifierHash(voters[2].secret, voters[2].nullifier)
        tx = await ballotsManagerDataManager.connect(voters[2].account).vote(bigIntToBytes(cnh3[0]), 1)
        callInputs3 = await getInputData(acc1.address, { secret: voters[2].secret, nullifier: voters[2].nullifier, txHash: tx.hash })

        await ballotsManagerDataManager.declareWinnerProposal()
    })

    describe("Claim share", () => {
        it("should work", async () => {
            await profitSharingDM.connect(voters[1].account).claimShare(callInputs2[0], callInputs2[1], callInputs2[2], callInputs2[3], callInputs2[4], callInputs2[5])
            expect(await profitSharingDM.nullifierHashes(bigIntToBytes(cnh2[1]))).eq(true)
            await profitSharingDM.connect(voters[2].account).claimShare(callInputs3[0], callInputs3[1], callInputs3[2], callInputs3[3], callInputs3[4], callInputs3[5])
            expect(await profitSharingDM.nullifierHashes(bigIntToBytes(cnh3[1]))).eq(true)
        })
        it("should not work to avoid double share withdraw", async () => {
            expect(await profitSharingDM.connect(voters[1].account).claimShare(callInputs2[0], callInputs2[1], callInputs2[2], callInputs2[3], callInputs2[4], callInputs2[5])).to.revertedWith("Already withdraw the share")
            expect(await profitSharingDM.connect(voters[2].account).claimShare(callInputs3[0], callInputs3[1], callInputs3[2], callInputs3[3], callInputs3[4], callInputs3[5])).to.revertedWith("Already withdraw the share")
        })
        it("should not work to avoid loser from withdraw", async () => {
            await expect(profitSharingDM.connect(voters[0].account).claimShare(callInputs1[0], callInputs1[1], callInputs1[2], callInputs1[3], callInputs1[4], callInputs1[5])).to.revertedWith("invalid Proof")
        })
    })
})