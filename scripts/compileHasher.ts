import path from 'path';
import fs from 'fs';
import { createCode, abi } from './utils/mimcsponge_gencontract'

const outputPath = path.join(__dirname, '..', 'artifacts','contracts', 'Hasher.json');

export function compileHasher(): void {
  const contract = {
    contractName: 'Hasher',
    abi: abi,
    bytecode: createCode('mimcsponge', 220),
  };

  fs.writeFileSync(outputPath, JSON.stringify(contract, null, 2));
}

compileHasher();