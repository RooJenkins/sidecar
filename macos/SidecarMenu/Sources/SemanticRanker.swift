import NaturalLanguage

/// Re-ranks search results using Apple's built-in sentence embeddings.
/// Instant, on-device, no external dependencies.
enum SemanticRanker {

    /// Re-rank BM25 candidates by semantic similarity to the query.
    /// Returns top N results sorted by similarity score.
    static func rerank(query: String, candidates: [SearchResult], topN: Int) -> [SearchResult] {
        guard !candidates.isEmpty, !query.isEmpty else { return Array(candidates.prefix(topN)) }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            Logger.log("Sentence embedding unavailable, returning BM25 order", source: "Semantic")
            return Array(candidates.prefix(topN))
        }

        let scored: [(result: SearchResult, similarity: Double)] = candidates.map { result in
            // Build a text representation of the candidate — include all available content
            var text = result.title
            if !result.summary.isEmpty { text += " " + result.summary }
            if !result.topics.isEmpty { text += " " + result.topics.joined(separator: " ") }
            if !result.snippet.isEmpty { text += " " + result.snippet }
            if let blocks = result.knowledgeBlocks {
                text += " " + blocks.joined(separator: " ")
            }

            let distance = embedding.distance(between: query, and: text)
            // distance is cosine distance: 0 = identical, 2 = opposite
            let similarity = 1.0 - (distance / 2.0)
            return (result, similarity)
        }

        let sorted = scored.sorted { $0.similarity > $1.similarity }
        Logger.log("Re-ranked \(candidates.count) candidates, top similarity: \(String(format: "%.3f", sorted.first?.similarity ?? 0))", source: "Semantic")

        return sorted.prefix(topN).map { $0.result }
    }
}
