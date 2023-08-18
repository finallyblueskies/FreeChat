//
//  ConversationView.swift
//  Mantras
//
//  Created by Peter Sugihara on 7/31/23.
//

import SwiftUI
import MarkdownUI

struct ConversationView: View {
  enum Position {
    case bottom
  }
  
  @Environment(\.managedObjectContext) private var viewContext
  
  var conversation: Conversation
  
  @ObservedObject var agent: Agent
  @State var pendingMessage: Message?
  
  var messages: [Message] {
    let set = conversation.messages as? Set<Message> ?? []
    return set.sorted {
      $0.createdAt! < $1.createdAt!
    }
  }
  
  var body: some View {
    ScrollViewReader { proxy in
      List(messages) { m in
        if m == messages.last {
          if m == pendingMessage {
            MessageView(pendingMessage!, overrideText: agent.pendingMessage == "" ? "..." : agent.pendingMessage)
              .id(Position.bottom)
              .onAppear {
                proxy.scrollTo(Position.bottom, anchor: .bottom)
              }
          } else {
            MessageView(m).id(Position.bottom)
          }
        } else {
          MessageView(m)
        }
      }
      .textSelection(.enabled)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        MessageTextField(conversation: conversation, onSubmit: { s in
          submit(s)
        })
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onReceive(
        agent.$pendingMessage.debounce(for: 1, scheduler: RunLoop.main)
      ) { _ in
        proxy.scrollTo(Position.bottom, anchor: .bottom)
      }

    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      Task {
        if agent.status == .ready, agent.prompt != conversation.prompt {
          agent.prompt = conversation.prompt ?? ""
          await agent.warmup()
        }
      }
    }
    .onChange(of: conversation) { nextConvo in
      Task {
        if agent.status == .ready, agent.prompt != conversation.prompt {
          agent.prompt = nextConvo.prompt ?? ""
          await agent.warmup()
        }
      }
    }
  }
  
  func submit(_ input: String) {
    if (agent.status == .processing) {
      Task {
        await agent.interrupt()
        submit(input)
      }
      return
    }
    let submitted = input
    _ = try! Message.create(text: submitted, fromId: Message.USER_SPEAKER_ID, conversation: conversation, inContext: viewContext)
    Task {
      let m = Message(context: viewContext)
      m.fromId = agent.id
      m.createdAt = Date()
      m.text = ""
      m.conversation = conversation
      pendingMessage = m
      agent.prompt = conversation.prompt ?? agent.prompt
      let currentConvo = conversation
      let text = await agent.listenThinkRespond(speakerId: Message.USER_SPEAKER_ID, message: submitted)
      currentConvo.prompt = agent.prompt
      pendingMessage = nil
      m.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      agent.pendingMessage = ""
      if m.text == "" {
        viewContext.delete(m)
      }
      try viewContext.save()
    }
  }
  
}

//struct ConversationView_Previews: PreviewProvider {
//  static var previews: some View {
//    let ctx = PersistenceController.preview.container.viewContext
//    let c = try! Conversation.create(ctx: ctx)
//    let _ = try! Message.create(text: "hello", conversation: c, inContext: ctx)
//    let _ = try! Message.create(text: "Hi", conversation: c, inContext: ctx)
//
//
//    ConversationView(conversation: c).environment(\.managedObjectContext, ctx)
//  }
//}

