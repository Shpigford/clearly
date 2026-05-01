import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SIZES_DEFAULT = [50_000, 100_000, 200_000];
const sizesArg = process.argv.find((a) => a.startsWith("--sizes="));
const SIZES = sizesArg
  ? sizesArg.replace("--sizes=", "").split(",").map((s) => parseInt(s, 10)).filter((n) => Number.isFinite(n))
  : SIZES_DEFAULT;

function generateMarkdown(targetWords) {
  const out = [];
  let wordCount = 0;
  out.push("---", "title: Synthetic perf doc", "tags: bench, perf", "---", "");
  const sample = "The quick brown fox jumps over the lazy dog. ".repeat(2);
  const linkLine = "Here is [a link](https://example.com) and **bold** text with `inline code`. ";
  const codeFence = ["```ts", "function example() {", "  return 42;", "}", "```"];
  const tableBlock = ["| Col A | Col B | Col C |", "|---|---|---|", "| 1 | 2 | 3 |", "| 4 | 5 | 6 |"];
  let line = 5;
  while (wordCount < targetWords) {
    if (line % 150 === 0 && line > 5) {
      tableBlock.forEach((t) => { out.push(t); wordCount += t.split(/\s+/).length; });
      line += tableBlock.length;
      out.push(""); line += 1;
      continue;
    }
    if (line % 80 === 0 && line > 5) {
      codeFence.forEach((c) => { out.push(c); wordCount += c.split(/\s+/).length; });
      line += codeFence.length;
      out.push(""); line += 1;
      continue;
    }
    if (line % 30 === 0) {
      out.push(`# Heading ${Math.floor(line / 30)}`);
      wordCount += 3; line += 1;
      continue;
    }
    const useLink = line % 4 === 0;
    const text = useLink ? linkLine + sample : sample;
    out.push(text);
    wordCount += text.split(/\s+/).length;
    line += 1;
  }
  return { md: out.join("\n"), lines: out.length, wordCount };
}

const dir = join(__dirname, "fixtures");
mkdirSync(dir, { recursive: true });
for (const target of SIZES) {
  const { md, wordCount } = generateMarkdown(target);
  const path = join(dir, `${target}.md`);
  writeFileSync(path, md, "utf8");
  console.log(`wrote ${path} (${wordCount.toLocaleString()} words, ${md.length.toLocaleString()} bytes)`);
}
