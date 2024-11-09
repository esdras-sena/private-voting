// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IBallotsManager {
    function vote(bytes32 _commitment, uint8 _vote) external;

    function winnerProposal() external view returns(address);

    function declareWinnerProposal() external;

    function addProposal(string memory _proposalName) external;
    function getBallots() external view returns(address[] memory);
}