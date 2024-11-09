// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "../interfaces/IIDManager.sol";
import "../interfaces/IProfitSharing.sol";
import "../interfaces/IDataPointRegistry.sol";
import "../interfaces/IDataIndex.sol";
import "../interfaces/IDataObject.sol";
import "./utils/OmnichainAddresses.sol";

interface IVerifier {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint256[3] memory _input
    ) external returns (bool);
}

interface IBallot {
    function isKnownRoot(bytes32 _root) external view returns (bool);

    function votes() external view returns (uint32);
}

contract ProfitSharingDO is IDataObject {
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
     * @notice Error thrown when the root is not one of the sotred roots
     * @param root The searched root
     */
    error CannotFindMerkleRoot(bytes32 root);

    /**
     * @notice Error thrown when the proof is invalid
     * @param nullifierHash The nullifierHash of the voter
     */
    error InvalidWithdrawProof(bytes32 nullifierHash);

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
    error InsufficientBalance(
        bytes32 diid,
        uint256 id,
        uint256 balance,
        uint256 value
    );

    /**
     * @notice Error thrown when the total supply is insufficient
     * @param id The id of the token
     * @param totalSupply The current total supply
     * @param value The requested amount
     * @dev This should never happen because we've already checked "from" balance
     */
    error InsufficientTotalSupply(
        uint256 id,
        uint256 totalSupply,
        uint256 value
    );

    /// @dev Error thrown when the params length mismatch
    error ArrayLengthMismatch();

    /**
     * @notice Event emitted when the DataIndex implementation is set
     * @param dp The DataPoint identifier
     * @param dataIndexImplementation The DataIndex implementation address
     */
    event DataIndexImplementationSet(
        DataPoint dp,
        address dataIndexImplementation
    );

    /**
     * @notice Data structure for storing the data to make the verification
     * @param verifier is the Verifier contract
     * @dev Data related to the DataPoint as a whole
     */
    struct DpData {
        IVerifier verifier;
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
        if (address(dps.dataIndexImplementation) != msg.sender)
            revert InvalidCaller(dp, msg.sender);
        _;
    }

    /// @inheritdoc IDataObject
    function setDIImplementation(DataPoint dp, IDataIndex newImpl) external {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            // Registering new DataPoint
            // Should be called by DataPoint Admin
            if (!_isDataPointAdmin(dp, msg.sender))
                revert InvalidCaller(dp, msg.sender);
        } else {
            // Updating the DataPoint
            // Should be called by current DataIndex or DataPoint Admin
            if (
                (address(dps.dataIndexImplementation) != msg.sender) &&
                !_isDataPointAdmin(dp, msg.sender)
            ) revert InvalidCaller(dp, msg.sender);
        }
        dps.dataIndexImplementation = newImpl;
        emit DataIndexImplementationSet(dp, address(newImpl));
    }

    // =========== Dispatch functions ============
    /// @inheritdoc IDataObject
    function read(
        DataPoint dp,
        bytes4 operation,
        bytes calldata data
    ) external view returns (bytes memory) {
        return _dispatchRead(dp, operation, data);
    }

    /// @inheritdoc IDataObject
    function write(
        DataPoint dp,
        bytes4 operation,
        bytes calldata data
    ) external onlyDataIndex(dp) returns (bytes memory) {
        return _dispatchWrite(dp, operation, data);
    }

    function _dispatchRead(
        DataPoint dp,
        bytes4 operation,
        bytes calldata data
    ) internal view virtual returns (bytes memory) {
        revert UnknownReadOperation(operation);
    }

    function _dispatchWrite(
        DataPoint dp,
        bytes4 operation,
        bytes calldata data
    ) internal virtual returns (bytes memory) {
        if (operation == IProfitSharing.setVerifier.selector) {
            address verifier = abi.decode(data, (address));
            _setVerifier(dp, verifier);
            return "";
        } else if (operation == IProfitSharing.claimShare.selector) {
            // decode and pass the data to the _claimShare function that will execute the verification
            (
                uint[2] memory a,
                uint[2][2] memory b,
                uint[2] memory c,
                bytes32 root,
                bytes32 nh,
                address r,
                address wp
            ) = abi.decode(
                    data,
                    (
                        uint[2],
                        uint[2][2],
                        uint[2],
                        bytes32,
                        bytes32,
                        address,
                        address
                    )
                );
            _claimShare(dp, a, b, c, root, nh, r, wp);
            return "";
        } else {
            revert UnknownWriteOperation(operation);
        }
    }

    // =========== Logic implementation ============

    // set the verifier contract
    function _setVerifier(DataPoint dp, address verifier) internal {
        DpData storage dpd = _dpData(dp);
        dpd.verifier = IVerifier(verifier);
    }

    // winner claim his share 
    function _claimShare(
        DataPoint dp,
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        bytes32 _root,
        bytes32 _nullifierHash,
        address _recipient,
        address winnerProposal
    ) internal {
        DpData storage dpd = _dpData(dp);
        // revert with custom error if the root is unkown
        if (!IBallot(winnerProposal).isKnownRoot(_root)) {
            revert CannotFindMerkleRoot(_root);
        }
        // Make sure to use a recent one
        // revert with custom error if the proof is invalid
        if (
            !dpd.verifier.verifyProof(
                a,
                b,
                c,
                [
                    uint256(_root),
                    uint256(_nullifierHash),
                    uint256(uint160(address(_recipient)))
                ]
            )
        ) {
            revert InvalidWithdrawProof(_nullifierHash);
        }
    }

    // =========== Helper functions ============

    function _isDataPointAdmin(
        DataPoint dp,
        address account
    ) internal view returns (bool) {
        (uint32 chainId, address registry, ) = DataPoints.decode(dp);
        ChainidTools.requireCurrentChain(chainId);
        return IDataPointRegistry(registry).isAdmin(dp, account);
    }

    function _diid(
        DataPoint dp,
        address account
    ) internal view returns (bytes32) {
        return IIDManager(msg.sender).diid(account, dp);
    }

    function _dpData(DataPoint dp) internal view returns (DpData storage) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        return dps.dpData;
    }

    function _tryDpData(
        DataPoint dp
    ) internal view returns (bool success, DpData storage) {
        (bool found, DataPointStorage storage dps) = _tryDataPointStorage(dp);
        if (!found) {
            return (false, dps.dpData);
        }
        return (true, dps.dpData);
    }

    function _dataPointStorage(
        DataPoint dp
    ) private view returns (DataPointStorage storage) {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            revert UninitializedDataPoint(dp);
        }
        return dpStorages[dp];
    }

    function _tryDataPointStorage(
        DataPoint dp
    ) private view returns (bool success, DataPointStorage storage) {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            return (false, dps);
        }
        return (true, dps);
    }
}
