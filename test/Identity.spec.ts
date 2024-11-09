import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { Voter, generateVoters } from "./helper/VotersGenerator";
import { encodeDP, setupERC7208 } from "./helper/setupERC7208";
import { CannesSBTDataManager } from "../typechain-types";

//  THIS TEST NEEDS TO BE REFACTORED
describe("SBT based on-chain identity test", async function () {
    let cannesSBTDataManager: CannesSBTDataManager;
    let voters: Voter[];
    let signers: any; 

    beforeEach(async ()=>{
        signers = await hre.ethers.getSigners()
        const owner = signers[0]
        const [dataIndex, dataPointRegistry] = await setupERC7208()
        await dataPointRegistry.allocate(owner.address)
        const diAddr = await dataIndex.getAddress()
        const dprAddr = await dataPointRegistry.getAddress()
        
        const soulBoundedTokenDO = await hre.ethers.deployContract("SoulBoundedTokenDO")
        const sbtDOAddr = await soulBoundedTokenDO.getAddress()
        cannesSBTDataManager = await hre.ethers.deployContract("CannesSBTDataManager", [owner.address,'CannesID', diAddr, sbtDOAddr, encodeDP(dprAddr, 1)])
        const csDM = await cannesSBTDataManager.getAddress()
        await dataIndex.allowDataManager(encodeDP(dprAddr, 1), csDM, true)
        await soulBoundedTokenDO.setDIImplementation(encodeDP(dprAddr, 1), diAddr)
        
        voters = generateVoters(6)
    
    })

    const issue = async (index: number) => {
        for(let i = 0; i < index; i++){
            await cannesSBTDataManager.issue(voters[i].account.address,`ipfs://Voter${i}`);    
        }
    }
    describe("SBT name", () => {
        it("it will check the SBT name",async ()=>{
            const name = await cannesSBTDataManager.name()
            expect(name).eq('CannesID')
        })
    })

    describe("Issue SBT", () => {
        it("check if SBT is correctly issued",async ()=>{
            await cannesSBTDataManager.issue(voters[0].account.address,"ipfs://Voter1");
            let tokenId = await cannesSBTDataManager.tokenOfOwner(voters[0].account.address);
            expect(tokenId).eq(1)
            await cannesSBTDataManager.issue(voters[1].account.address,"ipfs://Voter2");
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[1].account.address);
            expect(tokenId).eq(2)
            await cannesSBTDataManager.issue(voters[2].account.address,"ipfs://Voter3");
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[2].account.address);
            expect(tokenId).eq(3)
            await cannesSBTDataManager.issue(voters[3].account.address,"ipfs://Voter4");
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[3].account.address);
            expect(tokenId).eq(4)
            await cannesSBTDataManager.issue(voters[4].account.address,"ipfs://Voter5");
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[4].account.address);
            expect(tokenId).eq(5)
        })

        it("try to issue tokens with impostor account", async () => {
            await expect(cannesSBTDataManager.connect(signers[1]).issue(voters[5].account.address,"ipfs://Voter6")).to.revertedWith('is not the issuer')
        })
    })

    describe("Revoke SBT", () => {
        it("check if SBT is correctly revoked",async ()=>{
            await issue(5)
            let tokenId = await cannesSBTDataManager.tokenOfOwner(voters[4].account.address)
            await cannesSBTDataManager.revoke(voters[4].account.address, tokenId)
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[4].account.address)
            expect(tokenId).eq(0)
        })
        it("try to revoke tokens with impostor account", async () => {
            let tokenId = await cannesSBTDataManager.tokenOfOwner(voters[3].account.address)
            await expect(cannesSBTDataManager.connect(signers[1]).revoke(voters[3].account.address,tokenId)).to.revertedWith('is not the issuer')
        })
    })

    describe("Recover SBT", () => {
        it("check if SBT is correctly recovered", async ()=>{
            await issue(5)
            let tokenId = await cannesSBTDataManager.tokenOfOwner(voters[3].account.address)
            await cannesSBTDataManager.recover(voters[3].account.address, voters[5].account.address, tokenId)
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[3].account.address)
            expect(tokenId).eq(0)
            tokenId = await cannesSBTDataManager.tokenOfOwner(voters[4].account.address)
            expect(tokenId).eq(tokenId)
        })
        it("try to recover tokens with impostor account", async () => {
            let tokenId = await cannesSBTDataManager.tokenOfOwner(voters[4].account.address)
            await expect(cannesSBTDataManager.connect(signers[1]).recover(voters[4].account.address,voters[3].account.address, tokenId)).to.revertedWith('is not the issuer')
        })
    })
})
