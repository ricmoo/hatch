//import fs from "fs";

import { ethers } from "ethers";

import solc from "solc";

function copy(info: any): any {
    return JSON.parse(JSON.stringify(info));
}

export class _CodeError {
    readonly filename: string;
    readonly code: number;
    readonly message: string;
    readonly formattedMessage: string;

    constructor(filename: string, code: number, message: string, formattedMessage: string) {
        this.filename = filename;
        this.code = code;
        this.message = message;
        this.formattedMessage = formattedMessage;
    }
}

export class CodeError extends _CodeError { }

export class CodeWarning extends _CodeError { }

export class Code {
    filename: string;
    source: string;

    name: string;

    #info: any;
    #warnings: Array<CodeWarning>

    constructor(filename: string, source: string, name: string, info: any, warnings: Array<CodeWarning>) {
        this.filename = filename;
        this.source = source;
        this.name = name;

        this.#info = copy(info);
        this.#warnings = copy(warnings);
    }

    get abi(): ethers.utils.Interface {
        return new ethers.utils.Interface(this.#info.abi);
    }

    get bytecode(): string {
        return "0x" + this.#info.evm.bytecode.object;
    }

    get warnings(): Array<CodeWarning> {
        return copy(this.#warnings);
    }
}

export class Codebase extends Array<Code> {
    getContract(name: string): Code {
        const results = this.filter((c) => (c.name === name));
        if (results.length === 0) { throw new Error(`contract not found: ${ name }`); }
        if (results.length > 1) { throw new Error("ambiguous name: ${ name }"); }
        return results[0] as Code;
    }

    getSource(filename: string): string {
        const results = this.filter((c) => (c.filename === filename));
        if (results.length === 0) { throw new Error("filename not found"); }
        if (results.length > 1) { throw new Error("ambiguous filename"); }
        return results[0].source as string;
    }
}


function findImports(path: string): { contents: string } | { error: string } {
    return { error: "File not found" }
    /*
    return {
        contents: "contract foo() { }"
    }
    */
}

export function build(sources: Array<{ filename: string, content: string }>): Codebase {
    const input = {
        language: "Solidity",
        sources: sources.reduce((accum, { filename, content }) => {
            accum[filename] = { content };
            return accum;
        },  <Record<string, { content: string }>>{}),
        settings: {
          outputSelection: {
            "*": {
              "*": [ "*" ]
            }
          }
        }
    };

    const output = JSON.parse(solc.compile(JSON.stringify(input), { "import": findImports }));

    const warnings: Array<CodeWarning> = [ ];
    for (const error of output.errors) {
        if (error.severity !== "warning") {
            console.log(error.formattedMessage);
            throw new Error("Compile error");
        }
        warnings.push(new CodeWarning(error.sourceLocation.file, parseInt(error.errorCode), error.message, error.formattedMessage));
    }

    const result: Array<Code> = [ ];
    for (const filename in output.contracts) {
        const contracts = output.contracts[filename];
        for (const name in contracts) {
            const warns = warnings.filter((warning) => {
                return (warning.filename === filename) // @TODO: CheckRange
            });

            const source = sources.filter((s) => (s.filename === filename));
            if (source.length === 0) { throw new Error("internal: file not found"); }
            if (source.length > 1) { throw new Error("internal: duplicate filename"); }

            result.push(new Code(filename, source[0].content, name, contracts[name], warns));
        }
    }

    return new Codebase(...result);
}

