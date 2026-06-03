import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./model";
import { callModel } from "./model";
import { sendCodeEmail } from "./email";
import { subscribeToNewsletter } from "./newsletter";

const app = new Hono<{ Bindings: Env }>();
app.use("*", cors());

const enc = new TextEncoder();
const todayKey = () => new Date().toISOString().slice(0, 10).replace(/-/g, "");

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", enc.encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const randToken = () => {
  const a = new Uint8Array(24);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
};
const sixDigits = () => String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
const normEmail = (e: unknown) => String(e ?? "").trim().toLowerCase();
const validEmail = (e: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e);

app.get("/health", (c) => c.json({ ok: true }));

// 1) Start sign-in: email a 6-digit code.
app.post("/auth/start", async (c) => {
  const email = normEmail((await c.req.json().catch(() => ({})))?.email);
  if (!validEmail(email)) return c.json({ error: "Invalid email." }, 400);

  // Throttle code requests: max 5 per email per hour.
  const throttleKey = `start:${email}:${new Date().toISOString().slice(0, 13)}`;
  const count = parseInt((await c.env.RW_KV.get(throttleKey)) || "0", 10);
  if (count >= 5) return c.json({ error: "Too many requests. Try again later." }, 429);
  await c.env.RW_KV.put(throttleKey, String(count + 1), { expirationTtl: 3600 });

  const code = sixDigits();
  await c.env.RW_KV.put(`code:${email}`, await sha256(code), { expirationTtl: 600 });
  try {
    await sendCodeEmail(c.env, email, code);
  } catch (e) {
    return c.json({ error: `Couldn't send email: ${(e as Error).message}` }, 502);
  }
  return c.json({ ok: true });
});

// 2) Verify code → subscribe to newsletter → issue token.
app.post("/auth/verify", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const email = normEmail(body?.email);
  const code = String(body?.code ?? "").trim();
  if (!validEmail(email) || !/^\d{6}$/.test(code)) return c.json({ error: "Invalid email or code." }, 400);

  const stored = await c.env.RW_KV.get(`code:${email}`);
  if (!stored || stored !== (await sha256(code))) return c.json({ error: "Incorrect or expired code." }, 401);
  await c.env.RW_KV.delete(`code:${email}`);

  await subscribeToNewsletter(c.env, email); // non-fatal

  const token = randToken();
  await c.env.RW_KV.put(`tok:${token}`, JSON.stringify({ email, at: Date.now() }));
  return c.json({ token, email });
});

// 3) Rewrite: validate token, rate-limit, stream from the model.
app.post("/v1/rewrite", async (c) => {
  const auth = c.req.header("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const userRaw = token ? await c.env.RW_KV.get(`tok:${token}`) : null;
  if (!userRaw) return c.json({ error: "Not signed in." }, 401);

  const { systemPrompt, text } = await c.req.json().catch(() => ({}));
  if (typeof systemPrompt !== "string" || typeof text !== "string" || !text.trim()) {
    return c.json({ error: "Missing text." }, 400);
  }

  // Per-user + global daily caps.
  const day = todayKey();
  const perUserLimit = parseInt(c.env.PER_USER_DAILY_LIMIT || "50", 10);
  const globalLimit = parseInt(c.env.GLOBAL_DAILY_LIMIT || "2000", 10);
  const userKey = `cnt:${token}:${day}`;
  const globalKey = `cntall:${day}`;
  const userCount = parseInt((await c.env.RW_KV.get(userKey)) || "0", 10);
  const globalCount = parseInt((await c.env.RW_KV.get(globalKey)) || "0", 10);
  if (userCount >= perUserLimit) {
    return c.json({ error: `Daily free limit reached (${perUserLimit}/day). Try again tomorrow, or add your own key in Settings.` }, 429);
  }
  if (globalCount >= globalLimit) {
    return c.json({ error: "The free service is busy right now. Try again later, or add your own key in Settings." }, 429);
  }
  await c.env.RW_KV.put(userKey, String(userCount + 1), { expirationTtl: 172800 });
  await c.env.RW_KV.put(globalKey, String(globalCount + 1), { expirationTtl: 172800 });

  // Stream the model output back to the app as SSE-style `data:` lines.
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (t: string) => controller.enqueue(enc.encode(`data: ${JSON.stringify({ text: t })}\n\n`));
      try {
        await callModel(c.env, systemPrompt, text, send);
        controller.enqueue(enc.encode("data: [DONE]\n\n"));
      } catch (e) {
        controller.enqueue(enc.encode(`data: ${JSON.stringify({ error: (e as Error).message })}\n\n`));
      } finally {
        controller.close();
      }
    },
  });
  return new Response(stream, {
    headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "Connection": "keep-alive" },
  });
});

export default app;
