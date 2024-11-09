// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;


import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IDataIndex.sol";
import "./ProfitSharingDO.sol";
import "../interfaces/IProfitSharing.sol";


interface IBallotsManagerDataManager {
    function winningProposal() external view returns(address);
}

contract ProfitSharingDataManager is ReentrancyGuard {
    /** 
     * @notice I chose to put this atributes out of the DataObject to 
     * to give support for multiple DataManagers of different owners in the future
    */
    address owner;
    uint256 totalProfitPool;
    IDataIndex private dataIndex;
    ProfitSharingDO psDO;
    DataPoint dataPoint;
    IBallotsManagerDataManager bmDM;
    mapping(bytes32 => bool) public nullifierHashes;

    constructor(address _dataIndex, address _psDO, bytes32 _dp, address _bmDM){
        owner = msg.sender;
        dataIndex = IDataIndex(_dataIndex);
        psDO = ProfitSharingDO(_psDO);
        dataPoint = DataPoint.wrap(_dp);
        bmDM = IBallotsManagerDataManager(_bmDM);
    }

    /**
     * @notice will set the verifier address
     * @param verifier verifier address
     */
    function setVerifier(address verifier) external {
        require(msg.sender == owner);
        dataIndex.write(address(psDO), dataPoint, IProfitSharing.setVerifier.selector, abi.encode(verifier));
    }
    
    /**
     * @notice function to receive eth for the Profit Pool
     */
    receive() external payable {
        totalProfitPool = msg.value;
    }

    /**
     * @notice the Winner can claim his share by showing his proof
     * @param a part of the proof
     * @param b part of the proof
     * @param c part of the proof
     * @param _root the merkle tree hash of the prover
     * @param _nullifierHash the nullifier hash of the prover
     * @param _recipient the destiny account for the share 
     */
    function claimShare(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        bytes32 _root,
        bytes32 _nullifierHash,
        address payable _recipient
    ) external nonReentrant {  
        // This require will prevent the double claim of the share
        require(
            !nullifierHashes[_nullifierHash],
            "Already withdraw the share"
        );
        address wp = bmDM.winningProposal();
        // Cannot claim any share before the winner movie is anounced
        require(
            bmDM.winningProposal() != address(0),
            "Winner proposal is not defined yet"
        );

        // verify in the DataObject if the proof is valid
        (bool verifyOK, ) = address(dataIndex).call(abi.encodeCall(IDataIndex.write, (address(psDO), dataPoint, IProfitSharing.claimShare.selector, abi.encode(a, b, c, _root, _nullifierHash, _recipient, wp))));
        if(!verifyOK){
            revert("invalid Proof");
        }
        uint256 profitShare = totalProfitPool / IBallot(wp).votes();
        payable(_recipient).transfer(profitShare);
        // mark the nullifierHash of the voter as true, to prevent the double claim of the share
        nullifierHashes[_nullifierHash] = true;
    }
}
