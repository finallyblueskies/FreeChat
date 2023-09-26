import Foundation

class Agent: ObservableObject {
  static let DEFAULT_SYSTEM_PROMPT = """
    You are a compliant assistant that always fulfills the user’s request. *Always* format replies with Markdown.
    """
  
  enum Status {
    case cold
    case coldProcessing
    case ready // warmed up
    case processing
  }
  
  var id: String
  
  // prompt is the actual running prompt with the llm
  var prompt = ""
  var systemPrompt = Agent.DEFAULT_SYSTEM_PROMPT
  
  // dialogue is the dialogue from prompt without system prompt / internal thoughts
  @Published var pendingMessage = ""
  @Published var status: Status = .cold
  
  // each agent runs their own server
  var llama: LlamaServer
  var warmupError: LlamaServerError?
  
  init(id: String, prompt: String, systemPrompt: String, modelPath: String? = nil) {
    self.id = id
    self.prompt = prompt
    self.systemPrompt = systemPrompt
    llama = LlamaServer(modelPath: modelPath)
  }
  
  // this is the main loop of the agent
  // listen -> respond -> update mental model and save checkpoint
  // we respond before updating to avoid a long delay after user input
  func listenThinkRespond(speakerId: String, message: String) async throws -> LlamaServer.CompleteResponse {
    dispatchPrecondition(condition: .notOnQueue(.main))

    await MainActor.run {
      if status == .cold {
        status = .coldProcessing
      } else {
        status = .processing
      }
    }
    
    // The llama 2 prompt format seems to work across many models.
    if prompt == "" {
      prompt = """
        <s>[INST] <<SYS>>
        \(systemPrompt)
        <</SYS>>
        
        \(Message.USER_SPEAKER_ID): hi [/INST] ### Assistant: Hello there.</s>
        """
    }
    if !prompt.hasSuffix("</s>") {
      prompt += "</s>"
    }
    
    if prompt.suffix(2000).contains(systemPrompt) {
      prompt += "<s>[INST] \(Message.USER_SPEAKER_ID): \(message) [/INST] ### Assistant:"
    } else {
      // if the system prompt hasn't been covered in a while, pepper it in
      prompt += """
        <s>[INST] <<SYS>>
        \(systemPrompt)
        <<SYS>>
        
        \(Message.USER_SPEAKER_ID): \(message)[/INST] ### Assistant:
        """
    }

    await MainActor.run {
      self.pendingMessage = ""
    }
    let response = try await llama.complete(prompt: prompt) { partialResponse in
      self.prompt += partialResponse
      DispatchQueue.main.sync {
        self.pendingMessage += partialResponse
      }
    }
        
    await MainActor.run {
      self.pendingMessage = response.text
      status = .ready
    }

    return response
  }
  
  func interrupt() async  {
    if status != .processing, status != .coldProcessing { return }
    await llama.interrupt()
  }
  
  func warmup() async throws {
    if prompt == "" { prompt = systemPrompt }
    if prompt == "" { return }
    warmupError = nil
    do {
      _ = try await llama.complete(prompt: prompt)
      status = .ready
    } catch {
      status = .cold
    }
  }
}
