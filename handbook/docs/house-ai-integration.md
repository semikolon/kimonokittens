# House AI & Knowledge Base Integration

This document outlines the long-term vision for integrating the handbook with a centralized "House AI" to make our collective's knowledge instantly accessible.

## The Core Idea

The `handbook/` Git repository will serve as the **single source of truth** not just for human readers, but for an automated AI assistant. This AI will be accessible through various interfaces around the house, creating a seamless "ambient intelligence" layer.

### Key Components:

1.  **Automated Meeting Transcription:**
    *   **Source:** Use an AI transcription service (e.g., Superwhisper, Lily, OpenAI Whisper) to record and transcribe house meetings.
    *   **Ingestion:** The raw transcript is automatically committed to the handbook repo as a new proposal (e.g., `proposals/meetings/2025-07-30.md`).

2.  **Human-in-the-Loop Verification:**
    *   The handbook's two-step approval workflow is used to verify the transcript's accuracy. A meeting attendee must review and approve the notes before they are merged into the main knowledge base. This prevents "AI hallucinations" from becoming part of the official record.

3.  **The Knowledge Base (The Git Repo):**
    *   The AI's knowledge is strictly limited to the Markdown files within the `handbook/` directory. This includes:
        *   `docs/agreements.md`
        *   `meetings/*.md`
        *   Digitized rental contracts
        *   House rules and procedures

4.  **Query Interfaces:**
    *   **Voice:** A smart speaker in the kitchen (or other common areas) that can answer questions conversationally.
    *   **Chat:** A bot integrated into our collective's group chat (e.g., Messenger via a Matrix/Beeper bridge).
    *   **Web:** The handbook's own search interface.

## Use Cases

-   **Instant Answers:** "What's the WiFi password for guests?"
-   **Decision Recall:** "What did we decide about buying a new lawnmower last month?"
-   **Contradiction Detection:** "Does the guest policy conflict with the latest meeting notes on overnight stays?"
-   **Onboarding:** New members can simply ask the AI questions instead of reading through every document.

## Technical Architecture

The system is comprised of two main parts: the physical voice assistant hardware/software and the AI knowledge base backend.

### Voice Assistant Hardware & Software

*   **Central Server:** A Dell Optiplex 7010 running Pop!_OS hosts the core AI services in Docker containers.
*   **Speech-to-Text (STT):** [Whisper](https://github.com/openai/whisper) for accurate transcription.
*   **Text-to-Speech (TTS):** [Piper](https://github.com/rhasspy/piper) for a natural, fast, and locally-run voice.
*   **Microphone Satellites:** 2-3 Google Home units retrofitted to act as network-connected microphones. This is achieved using the **Wyoming Protocol** (an evolution of the "Onju" project), allowing custom firmware to stream audio to our server.
*   **Satellite Software:** `whisper-satellite` will run on the retrofitted devices to handle wake-word detection and audio streaming.

### Knowledge Base Backend (Retrieval-Augmented Generation - RAG)

To ensure the AI provides accurate answers based *only* on our approved documents, we will use a RAG architecture.

1.  **Indexing:** When a document is added or changed in the `handbook/` git repo, a `post-commit` hook triggers an indexing script. This script splits the document into chunks, converts them to vector embeddings, and stores them in a local vector database (e.g., ChromaDB).
2.  **Retrieval:** When a user asks a question, the system first retrieves the most semantically relevant document chunks from the vector database.
3.  **Generation:** These relevant chunks are then passed to a Large Language Model (LLM) along with the original question in a carefully crafted prompt, instructing the LLM to formulate an answer based only on the provided context. This grounds the AI's responses in our "single source of truth" and prevents hallucination.

This approach ensures that our shared knowledge is not only stored securely and transparently but is also actively useful and accessible in our daily lives. 