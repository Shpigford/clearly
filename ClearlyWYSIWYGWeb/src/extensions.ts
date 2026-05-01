// Single source of truth for the editor's extension list. Both the
// production entry and the round-trip test bundle import this so they stay
// in lockstep — divergence here would mask round-trip regressions.

import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "@tiptap/markdown";
import { CodeBlockLowlight } from "@tiptap/extension-code-block-lowlight";
import { common, createLowlight } from "lowlight";
import { Table } from "@tiptap/extension-table";
import { TableRow } from "@tiptap/extension-table-row";
import { TableHeader } from "@tiptap/extension-table-header";
import { TableCell } from "@tiptap/extension-table-cell";
import { Image } from "@tiptap/extension-image";
import { TaskList } from "@tiptap/extension-task-list";
import { TaskItem } from "@tiptap/extension-task-item";
import { PreserveBlockId } from "./preserve-block-id";
import { WikiLink } from "./extensions/wiki-link";
import { Details } from "./extensions/details";
import { HtmlBlock } from "./extensions/html-block";
import { Tag } from "./extensions/tag";
import { Highlight } from "./extensions/highlight";
import { Superscript, Subscript } from "./extensions/sup-sub";
import { Callout } from "./extensions/callout";
import { InlineMath, BlockMath } from "./extensions/math";
import { Mermaid } from "./extensions/mermaid";
import { FootnoteRef, FootnoteDef } from "./extensions/footnote";
import { Emoji } from "./extensions/emoji";
import { TOC } from "./extensions/toc";
import { Extension } from "@tiptap/core";
import { findPlugin } from "./find";
import { SlashMenu } from "./extensions/slash-menu";
import { WikiCompletion } from "./extensions/wiki-completion";
import { TagCompletion } from "./extensions/tag-completion";
import { BubbleMenu } from "./extensions/bubble";

const Find = Extension.create({
  name: "clearlyFind",
  addProseMirrorPlugins() {
    return [findPlugin()];
  },
});

const lowlight = createLowlight(common);

export const clearlyExtensions = [
  StarterKit.configure({ codeBlock: false }),
  CodeBlockLowlight.configure({ lowlight, defaultLanguage: null }),
  Markdown.configure({}),
  Table.configure({ resizable: false }),
  TableRow,
  TableHeader,
  TableCell,
  // Block-only for now: keeps the schema valid for the common standalone
  // image-only line shape (`![alt](url)`). Inline images inside paragraphs
  // are rarer in our corpus and fall back to source preservation.
  Image.configure({ inline: false, allowBase64: false }),
  TaskList,
  TaskItem.configure({ nested: true }),
  WikiLink,
  Details,
  HtmlBlock,
  Tag,
  Highlight,
  Superscript,
  Subscript,
  Callout,
  InlineMath,
  BlockMath,
  Mermaid,
  FootnoteRef,
  FootnoteDef,
  Emoji,
  TOC,
  Find,
  SlashMenu,
  WikiCompletion,
  TagCompletion,
  BubbleMenu,
  PreserveBlockId,
];
