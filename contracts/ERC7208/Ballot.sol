// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./utils/MerkleTreeWithHistory.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract Ballot is MerkleTreeWithHistory, ReentrancyGuard {
  
  // we store all commitments just to prevent accidental deposits with the same commitment
  mapping(bytes32 => bool) public commitments;
  address public ballotsManager;

  
  event Withdrawal(address to, bytes32 nullifierHash, address indexed relayer, uint256 fee);

  /**
    @dev The constructor
    @param _hasher the address of MiMC hash contract
    @param _merkleTreeHeight the height of deposits' Merkle Tree
    @param _bm the BallotsManager address
  */
  constructor(
    address _hasher,
    uint32 _merkleTreeHeight,
    address _bm
  ) MerkleTreeWithHistory(_merkleTreeHeight, _hasher) {
    ballotsManager = _bm;
  }

  /**
    @dev This function should be called from a disposable account for privacy reasons
    @param _commitment the note commitment, which is PedersenHash(nullifier + secret)
  */
  function vote(bytes32 _commitment) external nonReentrant returns (bytes32, bytes32[] memory , uint8[] memory){
    require(msg.sender == ballotsManager, "is not ballotsManager");
    require(!commitments[_commitment], "The commitment has been submitted");

    (bytes32 root, bytes32[] memory hashPairings, uint8[] memory hashDirections) = _insert(_commitment);
    commitments[_commitment] = true;

    return (root, hashPairings, hashDirections);
  }

  function votes() external view returns (uint32) {
    return nextIndex;
  }
  
}