# BM25 and Search Engines

Notes on how text search actually ranks results.

## Term frequency, inverse document frequency

The intuition: a word that appears many times in a document is probably what the document is about (TF). A word that appears in many documents in the corpus carries little information (low IDF). Score = TF × IDF was the early formula.

## What TF-IDF gets wrong

Linear scaling on term frequency — a document mentioning "kafka" 50 times shouldn't score 5x higher than a document mentioning it 10 times. There's a saturation effect, and TF-IDF doesn't capture it.

## BM25 fixes the saturation

BM25 (Best Match 25) introduces saturation via two parameters: `k1` controls how fast the TF score plateaus (typically 1.2-2.0), and `b` controls how much document length normalizes the score (typically 0.75). The result is way more intuitive ranking — more occurrences of a query term help, but with diminishing returns, and a 50-page document doesn't beat a one-paragraph document just because the term appears more times.

## SQLite's FTS5

The `bm25()` ranking function in FTS5 implements this directly. Cheaper than full Elastic/Lucene for moderate-sized corpora and fast enough for hundreds of thousands of documents on a laptop.

## When BM25 isn't enough

Synonyms, paraphrasing, abbreviations — BM25 only knows literal tokens. That's where dense embeddings (semantic search) earn their keep. Hybrid retrieval — BM25 + cosine over embeddings, fused via reciprocal-rank fusion — is the modern default.
