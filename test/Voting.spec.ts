import { expect } from "chai";
import hre from "hardhat";
import { bigIntToBytes, encodeDP, setupERC7208 } from "./helper/setupERC7208";
import { Voter, commitmentAndNullifierHash, generateVoters } from "./helper/VotersGenerator";
import { Ballot, BallotsManagerDataManager } from "../typechain-types";
import { compileHasher } from "../scripts/compileHasher";


//  THIS TEST NEEDS TO BE REFACTORED
describe("Voting test", async () =>{
    let ballotsManagerDataManager: BallotsManagerDataManager;
    let voters: Voter[];
    let signers: any; 

    beforeEach( async ()=>{
    signers = await hre.ethers.getSigners()
    const owner = signers[0]
  
    const [dataIndex, dataPointRegistry] = await setupERC7208()
    const diAddr = await dataIndex.getAddress()
    const dprAddr = await dataPointRegistry.getAddress()
    voters = generateVoters(6)

    const hJSON = require('./helper/Hasher.json')
    const factory = new hre.ethers.ContractFactory(hJSON.abi, hJSON.bytecode, owner);
    let hasher = await factory.deploy()
    const hasherAddr = await hasher.getAddress()

    const soulBoundedTokenDO = await hre.ethers.deployContract("SoulBoundedTokenDO")
    const sbtDOAddr = await soulBoundedTokenDO.getAddress()

    const cannesSBTDataManager = await hre.ethers.deployContract("CannesSBTDataManager", [owner.address,'CannesID', diAddr, sbtDOAddr, encodeDP(dprAddr, 1)])
    const csDM = await cannesSBTDataManager.getAddress()

    const ballotsManagerDO = await hre.ethers.deployContract("BallotsManagerDO")
    const bmDO = await ballotsManagerDO.getAddress()
    ballotsManagerDataManager = await hre.ethers.deployContract("BallotsManagerDataManager", [diAddr, bmDO, hasherAddr, encodeDP(dprAddr, 1), csDM])
    const bmDM = await ballotsManagerDataManager.getAddress()
    await dataPointRegistry.allocate(owner.address)
    await soulBoundedTokenDO.setDIImplementation(encodeDP(dprAddr, 1), diAddr)
    await ballotsManagerDO.setDIImplementation(encodeDP(dprAddr, 1), diAddr)
    await dataIndex.allowDataManager(encodeDP(dprAddr, 1), bmDM, true)
    await dataIndex.allowDataManager(encodeDP(dprAddr, 1), csDM, true)
    for(let i = 0; i<5; i++){
      await cannesSBTDataManager.issue(voters[i].account.address,`ipfs://Voter${i}`);
      await owner.sendTransaction({
        to: voters[i].account.address,
        value: hre.ethers.parseEther("1.0"), // Sends exactly 1.0 ether
      });
    }
    })
    
    const addMovies = async () => {
      await ballotsManagerDataManager.addProposal("Interstellar")
      await ballotsManagerDataManager.addProposal("Inception")
    }

    const vote = async (index: number) => {
      for(let i = 0; i< index;i++){
        if(i >= 2){
          let cnh1 = await commitmentAndNullifierHash(voters[i].secret, voters[i].nullifier)
          await ballotsManagerDataManager.connect(voters[i].account).vote(bigIntToBytes(cnh1[0]),1)  
          continue
        }
        let cnh1 = await commitmentAndNullifierHash(voters[i].secret, voters[i].nullifier)
        await ballotsManagerDataManager.connect(voters[i].account).vote(bigIntToBytes(cnh1[0]),0)
      }
    }
    
    describe("Test add Movies", ()=>{
      it("should add 2 movies to be voted", async () => {
          await addMovies()
          let ballots = await ballotsManagerDataManager.getBallots()
          expect(ballots.length).eq(2)
      })
      it("try to add proposal with impostor account", async ()=>{
        await expect(ballotsManagerDataManager.connect(signers[1]).addProposal("Joker 2")).to.revertedWith("You're not the owner")
      })
    })

    describe("Test Voting processes", ()=>{
      it("should check votes", async () => {
        await addMovies()
        await vote(5)
        let ballots = await ballotsManagerDataManager.getBallots()
        let B1 = await hre.ethers.getContractFactory("Ballot") 
        let b1 = B1.attach(ballots[0]) as Ballot
        let B2 = await hre.ethers.getContractFactory("Ballot")
        let b2 = B2.attach(ballots[1]) as Ballot 
        expect(await b1.votes()).eq(2)
        expect(await b2.votes()).eq(3)  
      })
      it("try to vote with account that does not have SBT Id", async () => {
        let cnh1 = await commitmentAndNullifierHash(voters[5].secret, voters[5].nullifier)
        await expect(ballotsManagerDataManager.connect(voters[5].account).vote(bigIntToBytes(cnh1[0]),0)).to.revertedWith("you don't have an on-chain ID")
      })
      it("should revert to avoid double voting", async () => {
        await addMovies()
        await vote(5)
        let cnh1 = await commitmentAndNullifierHash(voters[1].secret, voters[1].nullifier)
        await expect(ballotsManagerDataManager.connect(voters[1].account).vote(bigIntToBytes(cnh1[0]),0)).to.revertedWith("already voted")
      })
    })

    describe("Test if the winner is right",() => {
      it("Should check the winner movie", async () => {
        await addMovies()
        await vote(5)
        let ballots = await ballotsManagerDataManager.getBallots()
        await ballotsManagerDataManager.declareWinnerProposal()
        expect(await ballotsManagerDataManager.winningProposal()).eq(ballots[1])
      })
    })
    
})