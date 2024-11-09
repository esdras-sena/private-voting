// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "../interfaces/IIDManager.sol";
import "../interfaces/ISBT.sol";
import "../interfaces/IDataPointRegistry.sol";
import "../interfaces/IDataIndex.sol";
import "../interfaces/IDataObject.sol";
import "./utils/OmnichainAddresses.sol";

/**
 * @title Minimalistic Fungible Fractions Data Object
 * @notice DataObject with base funtionality of Fungible Fractions (Can be used for ERC1155-Compatible DataManagers)
 * @dev This contract exposes base functionality of Fungible Fraction tokens, including
 *      balanceOf, totalSupply, exists, transferFrom, mint, burn and their batch variants.
 *
 *      NOTE: This contract is expected to be used by a DataManager contract, which could
 *      implement a fungible token interface and provide more advanced features like approvals,
 *      access control, metadata management, etc. As may be an ERC1155 token.
 *
 *      This contract only emit basic events, it is expected that the DataManager contract will
 *      emit the events for the token operations
 */
contract SoulBoundedTokenDO is IDataObject {
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
     * 
     */
    struct DpData {
        uint256 tokenIdCounter;
        uint256 totalSupply;
        mapping (uint256=>string) uri;
        mapping (uint256=>address) owner;
        mapping (address=>uint256) token;
        mapping (uint256=>uint256) tokenTotalSupply;
    }

    /**
     * @notice Data structure for storing Fungible Fractions data of a user
     * @param ids Enumerable set of object (ERC20 token) ids
     * @param balances Mapping of object (ERC20 token) id to balance of the user owning diid
     * @param totalSupply total supply (ERC20 token)
     * @dev Data related to a specific user of a DataPoint (user identified by his DataIndex id)
     */
        struct DiidData {
        EnumerableSet.UintSet ids;
        mapping (uint256 => uint256) value;
        mapping(uint256 id => uint256 value) balances;
    }



    /**
     * @notice Data structure to store DataPoint data
     * @param dataIndexImplementation The DataIndex implementation set for the DataPoint
     * @param dpData The DataPoint data
     * @param dataIndexData Mapping of diid to user data
     */
    struct DataPointStorage {
        IDataIndex dataIndexImplementation;
        DpData dpData;
        mapping(bytes32 diid => DiidData) diidData;
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
        if (operation == ISBT.ownerOf.selector) {
            (uint256 id) = abi.decode(data, (uint256));
            return abi.encode(_ownerOf(dp, id));
        } else if (operation == ISBT.tokenOfOwner.selector) {
            (address acc) = abi.decode(data, (address));
            return abi.encode(_tokenOfOwner(dp, acc));
        } else if (operation == ISBT.totalSupply.selector) {
            return abi.encode(_totalSupply(dp));
        } else if (operation == ISBT.tokenURI.selector) {
            if (data.length != 0) revert WrongOperationArguments();
            (uint256 id) = abi.decode(data, (uint256));
            return abi.encode(_tokenURI(dp, id));
        } else {
            revert UnknownReadOperation(operation);
        }
    }

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal virtual returns (bytes memory) {
        if (operation == ISBT.issue.selector) {
            (address soul, string memory uri, uint256 id) = abi.decode(data, (address, string, uint256));
            _issue(dp, soul, uri, id);
            return "";
        } else if (operation == ISBT.revoke.selector) {
            (address soul, uint256 id) = abi.decode(data, (address, uint256));
            _revoke(dp, soul, id);
            return "";
        } else if (operation == ISBT.recover.selector) {
            (address oldSoul, address newSoul, uint256 id) = abi.decode(data, (address, address, uint256));
            _recover(dp, oldSoul, newSoul, id);
            return "";
        } else {
            revert UnknownWriteOperation(operation);
        }
    }

    // =========== Logic implementation ============

    
    function _issue(DataPoint dp, address _soul, string memory _uri, uint256 _tokenID) internal {
        DpData storage dpd = _dpData(dp);
        dpd.uri[dpd.tokenIdCounter] = _uri;
        dpd.owner[_tokenID] = _soul;
        dpd.token[_soul] = _tokenID;
        dpd.totalSupply+=1;
    }

    function _revoke(DataPoint dp, address _soul, uint256 _tokenId) internal {   
        DpData storage dpd = _dpData(dp);    
        delete dpd.uri[_tokenId];
        delete dpd.owner[_tokenId];
        delete dpd.token[_soul];
    }

    // commutnity recovery to avoid the private key commercialization
    function _recover(DataPoint dp, address _oldSoul, address _newSoul, uint256 _tokenId) internal {
        DpData storage dpd = _dpData(dp);  
        require(_oldSoul == dpd.owner[_tokenId], "current owner is not equal to _oldSoul");
        require(_tokenId == dpd.token[_oldSoul], "_oldSoul is not the owner of _tokenId");
        require(_newSoul != address(0), "_newSoul is equal to 0");
        dpd.owner[_tokenId] = _newSoul;
        delete dpd.token[_oldSoul];
        dpd.token[_newSoul] = _tokenId;
    }

    function _ownerOf(DataPoint dp, uint256 _tokenId) internal view returns (address){
        DpData storage dpd = _dpData(dp);
        return dpd.owner[_tokenId];
    }

    function _tokenOfOwner(DataPoint dp, address _soul) internal view returns (uint256) {
        DpData storage dpd = _dpData(dp);
        return dpd.token[_soul];
    }

    function _totalSupply(DataPoint dp) internal view returns (uint256) {
        DpData storage dpd = _dpData(dp);        
        return dpd.totalSupply;        
    }

    function _tokenURI(DataPoint dp, uint256 _tokenId) internal view returns (string memory){
        DpData storage dpd = _dpData(dp);
        return dpd.uri[_tokenId];
    }

    // functions for the ERC-20 token extension

    function _balanceOf(DataPoint dp, address account, uint256 id) internal view returns (uint256) {
        bytes32 diid = _tryDiid(dp, account);
        if (diid == 0) return 0;
        (bool success, DiidData storage od) = _tryDiidData(dp, diid);
        return success ? od.balances[id] : 0;
    }

    function _transferFrom(DataPoint dp, address from, address to, uint256 id, uint256 value) internal virtual {
        bytes32 diidFrom = _diid(dp, from);
        bytes32 diidTo = _diid(dp, to);
        DiidData storage diiddFrom = _diidData(dp, diidFrom);
        DiidData storage diiddTo = _diidData(dp, diidTo);
        _decreaseBalance(diiddFrom, id, value, dp, diidFrom);
        _increaseBalance(diiddTo, id, value, dp, diidTo);
    }

    function _mint(DataPoint dp, address to, uint256 id, uint256 value) internal virtual {
        bytes32 diidTo = _diid(dp, to);
        DiidData storage diiddTo = _diidData(dp, diidTo);
        _increaseBalance(diiddTo, id, value, dp, diidTo);
        
        DpData storage dpd = _dpData(dp);
        dpd.tokenTotalSupply[id] += value;
    }

    function _burn(DataPoint dp, address from, uint256 id, uint256 value) internal virtual {
        bytes32 diidFrom = _diid(dp, from);
        DiidData storage diiddFrom = _diidData(dp, diidFrom);
        _decreaseBalance(diiddFrom, id, value, dp, diidFrom);
        DpData storage dpd = _dpData(dp);
        uint256 totalSupply = dpd.tokenTotalSupply[id];
        if (totalSupply < value) revert InsufficientTotalSupply(id, totalSupply, value);
        unchecked {
            totalSupply -= value;
        }
        dpd.tokenTotalSupply[id] = totalSupply;
    }

    function _increaseBalance(DiidData storage diidd, uint256 id, uint256 value, DataPoint, bytes32) private {
        diidd.balances[id] += value;
        diidd.ids.add(id); // if id is already in the set, this call will return false, but we don't care
    }

    function _decreaseBalance(DiidData storage diidd, uint256 id, uint256 value, DataPoint, bytes32 diidFrom) private {
        uint256 diidBalance = diidd.balances[id];
        if (diidBalance < value) {
            revert InsufficientBalance(diidFrom, id, diidBalance, value);
        } else {
            unchecked {
                diidBalance -= value;
            }
            diidd.balances[id] = diidBalance;
            if (diidBalance == 0) {
                diidd.ids.remove(id);
            }
        }
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

    function _tryDiid(DataPoint dp, address account) internal view returns (bytes32) {
        try IIDManager(msg.sender).diid(account, dp) returns (bytes32 diid) {
            return diid;
        } catch {
            return 0;
        }
    }

    function _dpData(DataPoint dp) internal view returns (DpData storage) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        return dps.dpData;
    }

    function _diidData(DataPoint dp, bytes32 diid) internal view returns (DiidData storage) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        return dps.diidData[diid];
    }

    function _tryDpData(DataPoint dp) internal view returns (bool success, DpData storage) {
        (bool found, DataPointStorage storage dps) = _tryDataPointStorage(dp);
        if (!found) {
            return (false, dps.dpData);
        }
        return (true, dps.dpData);
    }

    function _tryDiidData(DataPoint dp, bytes32 diid) internal view returns (bool success, DiidData storage) {
        (bool found, DataPointStorage storage dps) = _tryDataPointStorage(dp);
        if (!found) {
            return (false, dps.diidData[bytes32(0)]);
        }
        DiidData storage diidd = dps.diidData[diid];
        if (diidd.ids.length() == 0) {
            // Here we use length of ids array as a flag that there is no data for the diid
            return (false, diidd);
        }
        return (true, diidd);
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
