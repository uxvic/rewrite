// Provider-agnostic model call. Streams text deltas via onDelta.
// Switch providers with the PROVIDER env var — the app never changes.

export interface Env {
  RW_KV: KVNamespace;
  PROVIDER: string;
  GEMINI_MODEL: string;
  PER_USER_DAILY_LIMIT: string;
  GLOBAL_DAILY_LIMIT: string;
  EMAIL_FROM: string;
  KIT_FORM_ID: string;
  // secrets:
  GEMINI_API_KEY: string;
  RESEND_API_KEY: string;
  KIT_API_KEY: string;
  TOKEN_SECRET: string;
  OPENROUTER_API_KEY?: string;
  GROQ_API_KEY?: string;
  ANTHROPIC_API_KEY?: string;
}

type Delta = (text: string) => void;

export async function callModel(env: Env, systemPrompt: string, text: string, onDelta: Delta): Promise<string> {
  switch (env.PROVIDER) {
    case "gemini": return callGemini(env, systemPrompt, text, onDelta);
    case "openrouter": return callOpenAICompatible(
      "https://openrouter.ai/api/v1/chat/completions",
      env.OPENROUTER_API_KEY || "", "deepseek/deepseek-chat-v3:free", systemPrompt, text, onDelta);
    case "groq": return callOpenAICompatible(
      "https://api.groq.com/openai/v1/chat/completions",
      env.GROQ_API_KEY || "", "llama-3.3-70b-versatile", systemPrompt, text, onDelta);
    default: return callGemini(env, systemPrompt, text, onDelta);
  }
}

// --- Google Gemini (streaming SSE) ---
async function callGemini(env: Env, systemPrompt: string, text: string, onDelta: Delta): Promise<string> {
  const model = env.GEMINI_MODEL || "gemini-2.5-flash";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${env.GEMINI_API_KEY}`;
  const body = {
    systemInstruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts: [{ text }] }],
    generationConfig: { maxOutputTokens: 2048 },
  };
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok || !res.body) {
    const msg = await res.text().catch(() => "");
    throw new Error(`Gemini ${res.status}: ${msg.slice(0, 300)}`);
  }
  let full = "";
  await readSSE(res.body, (data) => {
    try {
      const json = JSON.parse(data);
      const part = json?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof part === "string" && part.length) { full += part; onDelta(part); }
    } catch { /* ignore keepalives */ }
  });
  return full.trim();
}

// --- OpenAI-compatible (OpenRouter / Groq) streaming ---
async function callOpenAICompatible(url: string, key: string, model: string, systemPrompt: string, text: string, onDelta: Delta): Promise<string> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${key}` },
    body: JSON.stringify({
      model, stream: true,
      messages: [{ role: "system", content: systemPrompt }, { role: "user", content: text }],
    }),
  });
  if (!res.ok || !res.body) {
    const msg = await res.text().catch(() => "");
    throw new Error(`Model ${res.status}: ${msg.slice(0, 300)}`);
  }
  let full = "";
  await readSSE(res.body, (data) => {
    if (data === "[DONE]") return;
    try {
      const json = JSON.parse(data);
      const piece = json?.choices?.[0]?.delta?.content;
      if (typeof piece === "string" && piece.length) { full += piece; onDelta(piece); }
    } catch { /* ignore */ }
  });
  return full.trim();
}

// Reads an SSE stream and calls cb with each `data:` payload.
async function readSSE(stream: ReadableStream<Uint8Array>, cb: (data: string) => void) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, idx).trim();
      buffer = buffer.slice(idx + 1);
      if (line.startsWith("data:")) cb(line.slice(5).trim());
    }
  }
}
