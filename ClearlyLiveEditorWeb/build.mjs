import esbuild from "esbuild";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outFile = join(__dirname, "..", "Shared", "Resources", "live-editor", "live-editor.js");
mkdirSync(dirname(outFile), { recursive: true });

const ctx = await esbuild.context({
  entryPoints: [join(__dirname, "src", "index.ts")],
  outfile: outFile,
  bundle: true,
  format: "iife",
  platform: "browser",
  target: ["safari16", "chrome120"],
  sourcemap: false,
  minify: false,
  logLevel: "info"
});

if (process.argv.includes("--watch")) {
  await ctx.watch();
} else {
  await ctx.rebuild();
  await ctx.dispose();
}
