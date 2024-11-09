// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "../interfaces/IIDManager.sol";
import "../interfaces/IBallotsManager.sol";
import "../interfaces/IDataPointRegistry.sol";
import "../interfaces/IDataIndex.sol";
import "../interfaces/IDataObject.sol";
import "./utils/OmnichainAddresses.sol";

interface IBallot {
  function vote(bytes32 _commitment) external returns (bytes32 root, bytes32[] memory , uint8[] memory);
  function votes() external view returns (uint32);
}

contract BallotsManagerDO is IDataObject {
    using Arrays for uint256[];
    using Arrays for address[];
    using EnumerableSet for EnumerableSet.UintSet;

    /**
     * @notice Error thrown when the msg.sender is not the expected caller
     * @param dp The DataPoint identifier
     * @param sender The msg.sender address
     */
    error InvalidCaller(DataPoint dp, address sender);

    /**
     * @notice Error thrown when the DataPoint is not initialized with a DataIndex implementation
     * @param dp The DataPoint identifier
     */
    error UninitializedDataPoint(DataPoint dp);
    
    /// @dev Error thrown when the operation arguments are wrong
    error WrongOperationArguments();

    /**
     * @notice Error thrown when the read operation is unknown
     * @param selector The operation selector
     */
    error UnknownReadOperation(bytes4 selector);

    /**
     * @notice Error thrown when the write operation is unknown
     * @param selector The operation selector
     */
    error UnknownWriteOperation(bytes4 selector);
    
    /**
     * @notice Error thrown when the balance is insufficient
     * @param diid The DataIndex identifier
     * @param id The id of the token
     * @param balance The current balance
     * @param value The requested amount
     */
    error InsufficientBalance(bytes32 diid, uint256 id, uint256 balance, uint256 value);

    /**
     * @notice Error thrown when the total supply is insufficient
     * @param id The id of the token
     * @param totalSupply The current total supply
     * @param value The requested amount
     * @dev This should never happen because we've already checked "from" balance
     */
    error InsufficientTotalSupply(uint256 id, uint256 totalSupply, uint256 value);

    /// @dev Error thrown when the params length mismatch
    error ArrayLengthMismatch();

    /**
     * @notice Event emitted when the DataIndex implementation is set
     * @param dp The DataPoint identifier
     * @param dataIndexImplementation The DataIndex implementation address
     */
    event DataIndexImplementationSet(DataPoint dp, address dataIndexImplementation);

    /**
     * @notice Data structure for storing informations of ballots
     * @param proposals list of added proposals
     * @param winnerProposal the winner ballot proposal address
     * @param hasher the address of the hasher
     * @dev Data related to the DataPoint as a whole
     */
    struct DpData {
        IBallot[] proposals;
        address winnerProposal;
        address hasher;
    }


    /**
     * @notice Data structure to store DataPoint data
     * @param dataIndexImplementation The DataIndex implementation set for the DataPoint
     * @param dpData The DataPoint data
     */
    struct DataPointStorage {
        IDataIndex dataIndexImplementation;
        DpData dpData;
    }

    /// @dev Mapping of DataPoint to DataPointStorage
    mapping(DataPoint => DataPointStorage) private dpStorages;

    /**
     * @notice Modifier to check if the caller is the DataIndex implementation set for the DataPoint
     * @param dp The DataPoint identifier
     */
    modifier onlyDataIndex(DataPoint dp) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        if (address(dps.dataIndexImplementation) != msg.sender) revert InvalidCaller(dp, msg.sender);
        _;
    }

    /// @inheritdoc IDataObject
    function setDIImplementation(DataPoint dp, IDataIndex newImpl) external {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            // Registering new DataPoint
            // Should be called by DataPoint Admin
            if (!_isDataPointAdmin(dp, msg.sender)) revert InvalidCaller(dp, msg.sender);
        } else {
            // Updating the DataPoint
            // Should be called by current DataIndex or DataPoint Admin
            if ((address(dps.dataIndexImplementation) != msg.sender) && !_isDataPointAdmin(dp, msg.sender)) revert InvalidCaller(dp, msg.sender);
        }
        dps.dataIndexImplementation = newImpl;
        emit DataIndexImplementationSet(dp, address(newImpl));
    }

    // =========== Dispatch functions ============
    /// @inheritdoc IDataObject
    function read(DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory) {
        return _dispatchRead(dp, operation, data);
    }

    /// @inheritdoc IDataObject
    function write(DataPoint dp, bytes4 operation, bytes calldata data) external onlyDataIndex(dp) returns (bytes memory) {
        return _dispatchWrite(dp, operation, data);
    }

    function _dispatchRead(DataPoint dp, bytes4 operation, bytes calldata data) internal view virtual returns (bytes memory) {
        if (operation == IBallotsManager.winnerProposal.selector) {
            if (data.length != 0) revert WrongOperationArguments();
            return abi.encode(_winnerProposal(dp));
        } else if(operation == IBallotsManager.getBallots.selector){
            if (data.length != 0) revert WrongOperationArguments();
            return abi.encode(_getBallots(dp));
        } else {
            revert UnknownReadOperation(operation);
        }
    }

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal virtual returns (bytes memory) {
        if (operation == IBallotsManager.vote.selector) {
            (bytes32 _commitment, uint8 vote) = abi.decode(data, (bytes32, uint8));
            (bytes32 root, bytes32[] memory hashPairings, uint8[] memory hashDirections) = _vote(dp, _commitment, vote);
            return abi.encode(root, hashPairings, hashDirections);
        } else if (operation == IBallotsManager.declareWinnerProposal.selector) {
            _declareWinnerProposal(dp);
            return "";
        } else if (operation == IBallotsManager.addProposal.selector) {
            (address ballot) = abi.decode(data, (address));
            _addProposal(dp, ballot);
            return "";
        } else {
            revert UnknownWriteOperation(operation);
        }
    }

    // =========== Logic implementation ============
    // Should execute the vote for a movie
    function _vote(DataPoint dp, bytes32 _commitment, uint8 vote) internal returns (bytes32, bytes32[] memory , uint8[] memory){
        DpData storage dpd = _dpData(dp); 
        (bytes32 root, bytes32[] memory hashPairings, uint8[] memory hashDirections) = dpd.proposals[vote].vote(_commitment);
        return (root, hashPairings, hashDirections);
    }

    // declare the winner based on the number of commitments/votes
    function _declareWinnerProposal(DataPoint dp) internal {
        DpData storage dpd = _dpData(dp);
        
        address winner = address(0);
        uint32 mostVoted = 0;
        for (uint i = 0; i < dpd.proposals.length; i++) {
           if(dpd.proposals[i].votes() > mostVoted){
              winner = address(dpd.proposals[i]);
              mostVoted = dpd.proposals[i].votes();
           }
        }
        dpd.winnerProposal = winner;
    }

    // add new proposal address to the proposal list
    function _addProposal(DataPoint dp, address ballot) internal {
        DpData storage dpd = _dpData(dp);
        dpd.proposals.push(IBallot(address(ballot)));
    }

    // return the winner proposal
    function _winnerProposal(DataPoint dp) internal view returns(address) {
        DpData storage dpd = _dpData(dp);
        return dpd.winnerProposal;
    }

    // return the list of ballots
    function _getBallots(DataPoint dp) internal view returns(IBallot[] memory) {
        DpData storage dpd = _dpData(dp);
        return dpd.proposals;
    }
    
    // =========== Helper functions ============

    function _isDataPointAdmin(DataPoint dp, address account) internal view returns (bool) {
        (uint32 chainId, address registry, ) = DataPoints.decode(dp);
        ChainidTools.requireCurrentChain(chainId);
        return IDataPointRegistry(registry).isAdmin(dp, account);
    }

    function _diid(DataPoint dp, address account) internal view returns (bytes32) {
        return IIDManager(msg.sender).diid(account, dp);
    }

    function _dpData(DataPoint dp) internal view returns (DpData storage) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        return dps.dpData;
    }

    function _tryDpData(DataPoint dp) internal view returns (bool success, DpData storage) {
        (bool found, DataPointStorage storage dps) = _tryDataPointStorage(dp);
        if (!found) {
            return (false, dps.dpData);
        }
        return (true, dps.dpData);
    }

   
    function _dataPointStorage(DataPoint dp) private view returns (DataPointStorage storage) {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            revert UninitializedDataPoint(dp);
        }
        return dpStorages[dp];
    }

    function _tryDataPointStorage(DataPoint dp) private view returns (bool success, DataPointStorage storage) {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            return (false, dps);
        }
        return (true, dps);
    }
}
