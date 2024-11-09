pragma circom 2.0.0;

include "./utils/bitify.circom";
include "./utils/pedersen.circom";

// computes Pedersen(nullifier + secret)
template CommitmentHasher() {
    signal input nullifier;
    signal input secret;
    signal output commitment;
    signal output nullifierHash;

    component commitmentHasher = Pedersen(512);
    component nullifierHasher = Pedersen(256);
    component nullifierBits = Num2Bits(256);
    component secretBits = Num2Bits(256);
    nullifierBits.in <== nullifier;
    secretBits.in <== secret;
    for (var i = 0; i < 256; i++) {
        nullifierHasher.in[i] <== nullifierBits.out[i];
        commitmentHasher.in[i] <== nullifierBits.out[i];
        commitmentHasher.in[i + 256] <== secretBits.out[i];
    }

    commitment <== commitmentHasher.o;
    nullifierHash <== nullifierHasher.o;
}