// Tiptap Extension that adds a `preserveId` attribute to every block-level
// node type. The id is set once at mount (one per top-level child, matching
// the index of the block in the marked token list). When we serialize, we
// look up each PM child's preserveId to find its original source bytes.
//
// We don't serialize this attribute back to markdown — it lives only in the
// PM tree. parseHTML returns null so it never bleeds in via paste.

import { Extension } from "@tiptap/core";

// Every node type that can sit at the top level of `doc`. Anything new that
// can appear there must be added (otherwise setNodeAttribute below produces a
// node with an attribute the schema doesn't know about and validation fails).
const BLOCK_TYPES = [
  "paragraph",
  "heading",
  "codeBlock",
  "bulletList",
  "orderedList",
  "blockquote",
  "horizontalRule",
  "table",
  "image",
  "htmlBlock",
  "callout",
  "blockMath",
  "mermaid",
  "footnoteDef",
  "taskList",
  "toc",
  "details",
];

export const PreserveBlockId = Extension.create({
  name: "preserveBlockId",

  addGlobalAttributes() {
    return [
      {
        types: BLOCK_TYPES,
        attributes: {
          preserveId: {
            default: null,
            parseHTML: () => null,
            renderHTML: () => ({}),
            keepOnSplit: false,
          },
        },
      },
    ];
  },
});
