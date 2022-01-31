import { ethers } from "ethers";

import { build } from "./build.js";
import { Config } from "./config.js";

export class _CodeError {
    constructor(errorCode: number, message: string, formattedMessage: string) {
    }
}

export class CodeError extends _CodeError { }

export class CodeWarning extends _CodeError { }


export async function deploy(path: string = "."): Promise<null> {
    const config = Config.from(path);
    const sources = config.getSources()
    const codebase = build(sources);

    const provider = ethers.getDefaultProvider("http:/\/localhost:8545");
    const signer = (provider as ethers.providers.JsonRpcProvider).getSigner();

    //const provider = ethers.getDefaultProvider("ropsten");
    //const signer = new ethers.Wallet("0x5105c98838e8fa8b75dc875fd462163133a0d1969e48661d483c05b561bb3181", provider);
    //console.log("SIGNER", signer);
    async function deploy(name: string, args: Array<any>): Promise<ethers.Contract> {
        const code = codebase.getContract(name);
        const factory = new ethers.ContractFactory(code.abi, code.bytecode, signer);
        const contract = await factory.deploy(...args);
        return contract;
    }

    const ens = await deploy("TestENS", [ ]);
    const mlp = await deploy("HatchMaker", [ ens.address ]);
    await Promise.all([ ens.deployTransaction.wait(), mlp.deployTransaction.wait() ]);

    const ensName = "ricmoo.eth";
    const dnsName = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("\x06ricmoo\x03eth\x00"));

    const proxyAddr = await mlp.addressForName(dnsName);

    let tx = await ens.setOwner(ethers.utils.namehash(ensName), await signer.getAddress());
    await tx.wait();

    tx = await mlp.deployProxy(dnsName);
    await tx.wait();

    console.log("BB1");
    tx = await signer.sendTransaction({
        to: proxyAddr,
        value: ethers.utils.parseEther("1.0")
    });
    await tx.wait();

    const proxyCode = codebase.getContract("Proxy");
    const proxy = new ethers.Contract(proxyAddr, proxyCode.abi, signer);

    console.log("BB2");
    console.log("BB3", ethers.utils.formatEther(await provider.getBalance(proxyAddr)));
    tx = await proxy.execute(signer.getAddress(), "0x", ethers.utils.parseEther("0.1"), {
        gasLimit: 800000
    });
    console.dir(await tx.wait(), { depth: null });

    console.log("A", ethers.utils.formatEther(await provider.getBalance(signer.getAddress())));
    console.log("B", ethers.utils.formatEther(await provider.getBalance(proxyAddr)));

    return null;
}

(async function() {
    console.log(await deploy());
})().catch((error) => {
    console.log("HERE", error);
});
