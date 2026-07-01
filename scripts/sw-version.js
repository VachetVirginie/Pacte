import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const swPath = resolve(process.cwd(), "public/sw.js");
const sw = readFileSync(swPath, "utf8");
const version = new Date().toISOString();

if (!sw.includes("const BUILD_VERSION")) {
  writeFileSync(swPath, `const BUILD_VERSION = "${version}";\n${sw}`);
} else {
  writeFileSync(swPath, sw.replace(/const BUILD_VERSION = "[^"]*";/, `const BUILD_VERSION = "${version}";`));
}
