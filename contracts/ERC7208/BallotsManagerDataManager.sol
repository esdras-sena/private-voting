// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import './Ballot.sol';
import "../interfaces/IDataIndex.sol";
import "./BallotsManagerDO.sol";
import "../interfaces/IBallotsManager.sol";
import "./CannesSBTDataManager.sol";

contract BallotsManagerDataManager {
    /** 
     * @notice I chose to put this atributes out of the DataObject to 
     * to give support for multiple DataManagers of different owners in the future
    */
    mapping (address => string) public proposalName;
    mapping(uint256 => bool) public voted;
    address public owner;
    address public hasher;
    IDataIndex private dataIndex;
    BallotsManagerDO bmDO;
    DataPoint dataPoint;
    CannesSBTDataManager csdm;
    bool votingFase = true;

    /**
     * @notice event to anounce the winnerProposal
     * @param _winner address of the winner
     */
    event Winner(address _winner);

    /**
     * @notice event to anounce that a vote was casted, the parameters of 
     * this event will be used by the prover to verify the proof
     * @param root hash of the root of the tree
     * @param hashPairings hash of the roots that will recreate the tree
     * @param hashDirections directios of the hashPairings (0=left, 1= right)
     */
    event Voted(bytes32 root, bytes32[] hashPairings, uint8[] hashDirections);


    modifier onlyOwner() {
      require(msg.sender == owner, "You're not the owner");
      _;
    }

    constructor (address _dataIndex, address _bmDO, address _hasher, bytes32 _dp, address _csdm) {
        dataIndex = IDataIndex(_dataIndex);
        owner = msg.sender;
        hasher = _hasher;
        bmDO = BallotsManagerDO(_bmDO);
        dataPoint = DataPoint.wrap(_dp);
        csdm = CannesSBTDataManager(_csdm);
    }

    /**
     * @notice this function unlock the vote function
     */
    function openVoting() external onlyOwner{
        votingFase = true;   
    }

    /**
     * @notice the voter can cast his vote for his favorite movie
     * @param _commitment commintment of the voter to be added in the merkle tree, commitment = Hash(secret, nullifier)
     * @param _vote the voting option
     */
    function vote(bytes32 _commitment, uint8 _vote) external {
        uint256 token = csdm.tokenOfOwner(msg.sender);
        // this will prevent the double voting
        require(!voted[token], "already voted");
        require(votingFase, "winner was already declared");
        
        // verify if the voter has and valid onchain id
        require(token > 0, "you don't have an on-chain ID");
        
        (bytes32 root, bytes32[] memory hashPairings, uint8[] memory hashDirections) = abi.decode(dataIndex.write(address(bmDO), dataPoint, IBallotsManager.vote.selector, abi.encode(_commitment, _vote)), (bytes32, bytes32[], uint8[]));
        voted[token] = true;
        emit Voted(root, hashPairings, hashDirections);
    }

    /**
     * @notice return the winner proposal
     */
    function winningProposal() external view returns(address){
        return abi.decode(bmDO.read(dataPoint, IBallotsManager.winnerProposal.selector, ''), (address));
    }

    /**
     * @notice declare the winner proposal and ends the voting period
     */
    function declareWinnerProposal() external onlyOwner {
        require(this.winningProposal() == address(0), "Winner is already declared");
        dataIndex.write(address(bmDO), dataPoint, IBallotsManager.declareWinnerProposal.selector, '');
        address wp = abi.decode(bmDO.read(dataPoint, IBallotsManager.winnerProposal.selector, ''), (address));
        // after the winner is declared, the voting fase will be blocked, and can only be open again by the owner
        votingFase = false;
        emit Winner(wp);
    }

    /**
     * @notice add a proposal by deploying a Ballot contract for it
     * @param _proposalName name of the proposed movie
     */
    function addProposal(string memory _proposalName) external onlyOwner {
        /**
         * Deploy new ballot contract. I chose to divide the votes/commitments in diferent
         * contracts to avoid the high computational complexity of voting/commitment counting that can be created
         * by puting everything in a single contract
         */
        Ballot ballot = new Ballot(hasher, 10, address(bmDO));
        proposalName[address(ballot)] = _proposalName;
        dataIndex.write(address(bmDO), dataPoint, IBallotsManager.addProposal.selector, abi.encode(address(ballot)));
    }

    /**
     * @notice return the list of ballots
     */
    function getBallots() external view returns(IBallot[] memory) {
        return abi.decode(bmDO.read(dataPoint, IBallotsManager.getBallots.selector, ''), (IBallot[]));
    }

}