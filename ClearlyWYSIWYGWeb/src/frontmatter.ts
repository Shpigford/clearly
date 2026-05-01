// YAML frontmatter handling. Tiptap's markdown extension does not understand
// frontmatter — passed through, the leading `---` becomes a thematic break and
// the trailing `---` ends up parsed as a Setext heading. We strip it before
// hand-off and re-prepend on serialize so the on-disk bytes survive verbatim.
//
// Recognized shape: a file that starts with a line containing only `---`,
// followed by zero or more lines of YAML, followed by a closing line that's
// only `---`. The frontmatter ends with the trailing newline of the closing
// `---`. Everything after that is the body.

export interface SplitMarkdown {
  frontmatter: string | null;
  body: string;
}

// Match `---\n...\n---` at top, plus the closing newline AND any blank lines
// that sit between the frontmatter block and the body. Those blank lines are
// whitespace that belongs to the frontmatter conceptually — Tiptap's parser
// will drop them on re-serialize otherwise.
const FRONTMATTER_PATTERN = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n(?:[ \t]*\r?\n)*|$)/;

export function splitFrontmatter(md: string): SplitMarkdown {
  if (!md.startsWith("---")) {
    return { frontmatter: null, body: md };
  }
  const match = FRONTMATTER_PATTERN.exec(md);
  if (!match) {
    return { frontmatter: null, body: md };
  }
  const frontmatter = md.slice(0, match[0].length);
  const body = md.slice(match[0].length);
  return { frontmatter, body };
}

export function joinFrontmatter(frontmatter: string | null, body: string): string {
  if (frontmatter == null) return body;
  return frontmatter + body;
}
