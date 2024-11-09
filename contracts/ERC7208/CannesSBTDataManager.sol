// SPDX-License-Identifier: MIT

// This code bellow comes from my old github account https://github.com/esdras-santos/Nethermind-intrade/blob/main/contracts/NethermindSBT.sol
pragma solidity 0.8.28;

import "../interfaces/ISBT.sol";
import "../interfaces/IDataIndex.sol";
import "./SoulBoundedTokenDO.sol";

contract CannesSBTDataManager is ISBT {
    address private issuer;
    string public name;
    uint256 private tokenIdCounter;
    IDataIndex private dataIndex;
    SoulBoundedTokenDO sbtDO;
    DataPoint dataPoint;

    modifier onlyIssuer() {
        require(msg.sender == issuer, "is not the issuer");
        _;
    }

    constructor(address _issuer, string memory _name, address _dataIndex, address _sbtDO, bytes32 _dp) {
        issuer = _issuer;
        name = _name;
        dataIndex = IDataIndex(_dataIndex);
        sbtDO = SoulBoundedTokenDO(_sbtDO);
        dataPoint = DataPoint.wrap(_dp);
        tokenIdCounter = 1;
    }

    /**
     * @notice issue a onchain id token
     * @param _soul the holder of the onchain id
     * @param _uri metadata link of the id
     */
    function issue(address _soul, string memory _uri) external onlyIssuer {
        require(_soul != address(0), "soul is zero address");
        dataIndex.write(address(sbtDO), dataPoint, ISBT.issue.selector, abi.encode(_soul, _uri, tokenIdCounter));
        emit Issued(_soul, tokenIdCounter);
        tokenIdCounter += 1;
    }

    /**
     * @notice rovoke an id of a specific soul(account)
     * @param _soul account that will have his onchain id revoked
     * @param _tokenId onchain id
     */
    function revoke(address _soul, uint256 _tokenId) external onlyIssuer {
        dataIndex.write(address(sbtDO), dataPoint, ISBT.revoke.selector, abi.encode(_soul, _tokenId));
        emit Revoked(_soul, _tokenId);
    }

    /**
     * @notice recovering of an id for a new account
     * @param _oldSoul old soul
     * @param _newSoul new soul
     * @param _tokenId onchain id
     */
    function recover(
        address _oldSoul,
        address _newSoul,
        uint256 _tokenId
    ) external onlyIssuer {
        dataIndex.write(address(sbtDO), dataPoint, ISBT.recover.selector, abi.encode(_oldSoul,_newSoul,_tokenId));
        emit Recovered(_oldSoul, _newSoul, _tokenId);
    }

    /**
     * @notice return the owner account of the onchain id
     * @param _tokenId onchain id
     */
    function ownerOf(uint256 _tokenId) external view returns (address) {
        return abi.decode(sbtDO.read(dataPoint, ISBT.ownerOf.selector, abi.encode(_tokenId)), (address));
    }

    /**
     * @notice return the onchain id of the soul
     * @param _soul account of the owner
     */
    function tokenOfOwner(address _soul) external view returns (uint256) {
        return abi.decode(sbtDO.read(dataPoint, ISBT.tokenOfOwner.selector, abi.encode(_soul)), (uint256));
    }

    /**
     * @notice return the total of issued onchain ids
     */
    function totalSupply() external view returns (uint256) {
        return abi.decode(sbtDO.read(dataPoint, ISBT.totalSupply.selector, ''), (uint256));
    }

    /**
     * @notice return the URI that contains the metadata for the onchain id
     * @param _tokenId onchain id
     * @dev I propose that the metadata should also use Zero Knowled Proof in order
     * to increase even more the anonimity of the voter, in this way we can prove the identity
     * without revealing nothing about the voter
     */
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        return abi.decode(sbtDO.read(dataPoint, ISBT.tokenURI.selector, abi.encode(_tokenId)), (string));
    }
}
