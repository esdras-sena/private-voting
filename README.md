# Cannes Private Voting
This project is a privacy-preserving, on-chain identity and voting system using ERC-7208 to manage secure voting and profit-sharing.

## Overview
This protocol allows individuals to cast votes without revealing their identities. Zero-knowledge proofs and OnchainID are employed to verify the legitimacy of votes and the claim of share without exposing any personal information, ensuring that all counted votes are valid.

## Key Features
ERC7208: all the code is composable, mutable and extensible thanks to ERC7208
Anonymity: Voter identities and choices remain private, inspired by the privacy architecture of Tornado Cash.
zk-SNARKs for Privacy: The protocol uses zk-SNARK proofs to cast vote and claim share.
Profit-Sharing Mechanism: Integrated into the system is a profit-sharing component that distributes a portion of the protocol's revenue among the voters that voted for the winner movie.
Reliability: A robust system architecture ensures the correct count of valid votes without exposing voters' information.
Soul Bounded Tokens: soul bounded tokens(SBT) are used to make onchainIDs, so in this way we can make sure that is 1 vote per person


## How It Works
Registration: Voters are registered through a secure process , where they obtain a SBT for his ticket, this SBT represent voting eligibility without revealing the identity of the owner.
Voting: Voters submit the commitment along with their vote choice. These proofs confirm the voter's eligibility and the vote’s validity.
Profit Distribution: A fraction of the winner movie revenue is shared among the ones who voted for
the movie, this share can be claimed after the verification of the proof


## Project Structure
ERC7208: is used as base for the project structure
zk-SNARKs: Zero-knowledge proofs for private vote validation.
SBT contracts: Contracts to issue, revoke and recover onchainIDs
Ballots contracts: Contracts to execute the vote process.
Profit Sharing contracts: Contracts that verify the proof of the claimer and distributes the share

## Security measures
In order to cast a vote, the voter should send the commitment hash, the commitment hash is the hash of the secret and nullifier (Hash(secret, nullifier))

### disposable account
A disposable account will be generated using the secret, this disposable account will be linked to the onchainID of the voter, this is done to improve privacy when casting the vote.

### store critical informations 
The secret, nullifier and txHash of the transaction should be stored in the local storage of the device, this informations are used to generate the proof to prove that the voter cast his vote 
to the proposal


## Getting Started
Clone the repository:

`git clone https://github.com/esdras-sena/private-voting`
`cd private-voting`

Install dependencies:

`npm install`

Compile contracts:

`npx hardhat compile`

Run tests:

`npx hardhat test`

## Acknowledgments
Tornado Cash: The architecture and approach of the privacy in this system are heavily inspired by Tornado Cash’s zk-SNARKs-based anonymity mechanism.
