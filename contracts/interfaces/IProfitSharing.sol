interface IProfitSharing {
    function setVerifier(address verifier) external;
    function claimShare(
        bytes calldata _proof,
        bytes32 _root,
        bytes32 _nullifierHash,
        address payable _recipient,
        address winninProposal
    ) external;
}