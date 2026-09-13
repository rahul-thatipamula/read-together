import Foundation
import llama

/// Thin actor around the llama.cpp C API. One model + one context at a time.
/// Loaded lazily, freed on `unload()` and on app termination.
actor LlamaEngine {
    struct Message { let role: String; let content: String }

    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private(set) var loadedModelId: String?
    private var cancelled = false
    private static var backendReady = false

    let contextSize: UInt32 = 8192

    var isLoaded: Bool { ctx != nil }

    func load(modelId: String, path: URL) throws {
        if loadedModelId == modelId, ctx != nil { return }
        unload()
        if !Self.backendReady {
            llama_backend_init()
            llama_log_set({ level, text, _ in
                if level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue, let text { fputs(String(cString: text), stderr) }
            }, nil)
            Self.backendReady = true
        }
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99
        guard let m = llama_model_load_from_file(path.path, mp) else {
            throw EngineError.loadFailed("Could not load model file")
        }
        var cp = llama_context_default_params()
        cp.n_ctx = contextSize
        cp.n_batch = 1024
        cp.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        cp.n_threads_batch = cp.n_threads
        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            throw EngineError.loadFailed("Could not create context")
        }
        model = m
        ctx = c
        vocab = llama_model_get_vocab(m)
        loadedModelId = modelId
    }

    func unload() {
        if let c = ctx { llama_free(c) }
        if let m = model { llama_model_free(m) }
        ctx = nil
        model = nil
        vocab = nil
        loadedModelId = nil
    }

    func cancel() { cancelled = true }

    /// Streams generated text pieces. Applies the model's own chat template.
    func generate(messages: [Message], temperature: Float = 0.3, maxTokens: Int = 1024,
                  onPiece: @escaping @Sendable (String) -> Void) throws -> String {
        guard let ctx, let model, let vocab else { throw EngineError.notLoaded }
        cancelled = false

        let prompt = try applyTemplate(model: model, messages: messages)
        var tokens = tokenize(vocab: vocab, text: prompt, addSpecial: true)
        let budget = Int(contextSize) - maxTokens - 8
        if tokens.count > budget {
            // Keep the tail of the prompt (question + most relevant passages are last).
            tokens = Array(tokens.suffix(budget))
        }

        llama_memory_clear(llama_get_memory(ctx), true)

        // Prompt processing in batches.
        let nBatch = 1024
        var i = 0
        while i < tokens.count {
            let n = min(nBatch, tokens.count - i)
            let rc = tokens.withUnsafeMutableBufferPointer { buf -> Int32 in
                var batch = llama_batch_get_one(buf.baseAddress! + i, Int32(n))
                return llama_decode(ctx, batch)
            }
            if rc != 0 { throw EngineError.decodeFailed(rc) }
            i += n
        }

        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(smpl) }
        llama_sampler_chain_add(smpl, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        var output = ""
        var pending = [UInt8]()   // bytes of a not-yet-complete UTF-8 sequence
        var produced = 0
        var buf = [CChar](repeating: 0, count: 512)

        while produced < maxTokens, !cancelled {
            var tok = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }
            let n = llama_token_to_piece(vocab, tok, &buf, Int32(buf.count), 0, false)
            if n > 0 {
                pending.append(contentsOf: buf[0..<Int(n)].map { UInt8(bitPattern: $0) })
                if let s = String(bytes: pending, encoding: .utf8) {
                    pending.removeAll()
                    output += s
                    onPiece(s)
                }
            }
            var batch = llama_batch_get_one(&tok, 1)
            if llama_decode(ctx, batch) != 0 { break }
            produced += 1
        }
        return output
    }

    // MARK: - helpers

    private func tokenize(vocab: OpaquePointer, text: String, addSpecial: Bool) -> [llama_token] {
        let utf8 = Array(text.utf8)
        var out = [llama_token](repeating: 0, count: utf8.count + 16)
        let n = utf8.withUnsafeBufferPointer { p in
            llama_tokenize(vocab, p.baseAddress, Int32(utf8.count), &out, Int32(out.count), addSpecial, true)
        }
        if n < 0 {
            out = [llama_token](repeating: 0, count: Int(-n))
            _ = utf8.withUnsafeBufferPointer { p in
                llama_tokenize(vocab, p.baseAddress, Int32(utf8.count), &out, Int32(out.count), addSpecial, true)
            }
            return out
        }
        return Array(out.prefix(Int(n)))
    }

    private func applyTemplate(model: OpaquePointer, messages: [Message]) throws -> String {
        let tmpl = llama_model_chat_template(model, nil)
        // Keep C strings alive for the duration of the call.
        let roles = messages.map { strdup($0.role)! }
        let contents = messages.map { strdup($0.content)! }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        var chat = zip(roles, contents).map { llama_chat_message(role: UnsafePointer($0), content: UnsafePointer($1)) }

        let total = messages.reduce(0) { $0 + $1.content.utf8.count + 32 }
        var buf = [CChar](repeating: 0, count: total * 2 + 256)
        var n = llama_chat_apply_template(tmpl, &chat, chat.count, true, &buf, Int32(buf.count))
        if n > Int32(buf.count) {
            buf = [CChar](repeating: 0, count: Int(n) + 1)
            n = llama_chat_apply_template(tmpl, &chat, chat.count, true, &buf, Int32(buf.count))
        }
        if n < 0 {
            // Unknown template: fall back to ChatML, which most instruct models tolerate.
            return messages.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
        }
        return String(decoding: buf[0..<Int(n)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    enum EngineError: LocalizedError {
        case notLoaded, loadFailed(String), decodeFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .notLoaded: return "No model is loaded."
            case .loadFailed(let s): return s
            case .decodeFailed(let rc): return "Model failed to process the prompt (code \(rc))."
            }
        }
    }
}
