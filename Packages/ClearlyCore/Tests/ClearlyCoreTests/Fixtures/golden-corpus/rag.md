---
title: Retrieval-Augmented Generation
tags: [ai, llm]
---

# RAG: Retrieval-Augmented Generation

The pattern where you fetch relevant context from a corpus before asking the LLM, instead of fine-tuning the model on the corpus directly.

## Why RAG over fine-tuning

Cheaper to update (just edit the corpus), citations come for free (you know which document the answer drew from), works with any base model. Fine-tuning is for changing behavior or style; RAG is for adding knowledge.

## The basic loop

1. Embed the user's question with a sentence-embedding model.
2. Cosine-similarity search over a vector store of pre-embedded documents.
3. Take the top-K hits, splice them into the prompt as context.
4. Ask the LLM to answer over only that context, with citations.

## What goes wrong

The embedder is the load-bearing piece. Small models (~384 dim) miss obvious matches when the corpus has noise. Hybrid retrieval — semantic + keyword (bm25) — catches what each method alone misses. Reciprocal-rank fusion is the standard combiner.

## Chunking

One embedding per long document mean-pools everything into one vector. Better to chunk by section heading (or sliding window) and embed each chunk separately. Anthropic's contextual-retrieval paper reports +35% recall from prepending document title + section path to each chunk's embed text.
