import fs from "fs";
import { dirname, join, resolve } from "path";

function findConfig(path: string): string {
    while (true) {
        const filename = join(path, "ethers-build.json");
        console.log(filename);
        if (fs.existsSync(filename)) { return filename; }
        if (path === dirname(path)) { break; }
        path = dirname(path);
    }
    throw new Error("no config found");
}

export class Config {
    readonly path: string;

    readonly #config: any;

    constructor(path: string = ".") {
        this.path = findConfig(resolve(path));
        this.#config = JSON.parse(fs.readFileSync(this.path).toString());
        console.log(this.#config);
    }

    resolve(path: string): string {
        return resolve(dirname(this.path), path);
    }

    getSources(): Array<{ filename: string, content: string }> {
        const result: Array<{ filename: string, content: string }> = [ ];
        for (const filename of (this.#config.contracts || [])) {
            // @TODO: handle folders
            const content = fs.readFileSync(this.resolve(filename)).toString();
            result.push({ filename, content });
        }
        return result;
    }

    static from(path: string = "."): Config {
        return new Config(path);
    }
}
