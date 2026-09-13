import Foundation

struct CatalogModel: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let fileName: String
    let sizeBytes: Int64
    let minRamGB: Int
    let description: String
}

enum ModelCatalog {
    private static let GB: Int64 = 1 << 30

    static let all: [CatalogModel] = [
        CatalogModel(
            id: "qwen3-4b", name: "Qwen3 4B",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!,
            fileName: "Qwen3-4B-Q4_K_M.gguf", sizeBytes: 2_497_280_256, minRamGB: 8,
            description: "Fast and sharp. Best pick for 8–16 GB machines."),
        CatalogModel(
            id: "qwen3-8b", name: "Qwen3 8B",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf")!,
            fileName: "Qwen3-8B-Q4_K_M.gguf", sizeBytes: 5_027_783_488, minRamGB: 16,
            description: "Best explanations at this size. Recommended for 16 GB+."),
        CatalogModel(
            id: "gemma3-4b", name: "Gemma 3 4B",
            url: URL(string: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!,
            fileName: "gemma-3-4b-it-Q4_K_M.gguf", sizeBytes: 2_489_894_016, minRamGB: 8,
            description: "Very natural, readable answers. Light on memory."),
        CatalogModel(
            id: "gemma3-12b", name: "Gemma 3 12B",
            url: URL(string: "https://huggingface.co/unsloth/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q4_K_M.gguf")!,
            fileName: "gemma-3-12b-it-Q4_K_M.gguf", sizeBytes: 7_300_778_336, minRamGB: 24,
            description: "Deeper understanding, slower. For 24 GB+ machines."),
        CatalogModel(
            id: "llama3.2-3b", name: "Llama 3.2 3B",
            url: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf", sizeBytes: 2_019_377_696, minRamGB: 8,
            description: "Fastest option. Good for quick lookups."),
    ]

    static func find(_ id: String) -> CatalogModel? { all.first { $0.id == id } }
}
