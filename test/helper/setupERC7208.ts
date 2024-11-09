import hre from "hardhat";

const PREFIX = 0x44500000
const chainId = 31337; // Replace this with the actual chain ID

export async function setupERC7208(): Promise<any[]> {
    const [owner] = await hre.ethers.getSigners();
    const dataPointRegistry = await hre.ethers.deployContract("DataPointRegistry")
   
    const dataIndex = await hre.ethers.deployContract("DataIndex");
    
    
    
    return [dataIndex, dataPointRegistry]
}

export function encodeDP(registry: string, id: number): string {
    const registryBigInt = BigInt(registry);
    const idBigInt = BigInt(id);
    const prefixBigInt = BigInt(PREFIX);
    const chainIdBigInt = BigInt(chainId);

    // Perform the bit shifting and OR operations
    const encodedData = (prefixBigInt << 224n) |
                        (idBigInt << 192n) |
                        (chainIdBigInt << 160n) |
                        registryBigInt;

    // Return as a 32-byte hex string
    
    return hre.ethers.zeroPadBytes(hre.ethers.hexlify(bigIntToBytes(encodedData)), 32);
}

export function bigIntToBytes(bigInt: bigint): Uint8Array {
    const bytes = new Uint8Array(32);
    let temp = bigInt;

    for (let i = 32 - 1; i >= 0; i--) {
        bytes[i] = Number(temp % BigInt(256)); // Ensure the divisor is BigInt(256)
        temp = temp / BigInt(256); // Ensure the divisor is BigInt(256)
    }

    return bytes;
}