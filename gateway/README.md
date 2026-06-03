# Rewrite Gateway

A tiny Cloudflare Worker that lets the **Rewrite** app offer **free models with zero key setup**.
Users sign in with their email (6-digit code) → they're added to your **newsletter** → they can use the
app. Your model API key stays a server-side secret; it is **never** shipped in the app.

```
app ──email/code──▶ /auth/start, /auth/verify ──▶ Kit (subscribe) + issue token
app ──Bearer token─▶ /v1/rewrite ──(rate-limited)──▶ Gemini 2.5 Flash ──stream──▶ app
```

## What you need (free accounts)
1. **Cloudflare** — to host the Worker.
2. **Google AI Studio** — free Gemini API key: https://aistudio.google.com/apikey
3. **Resend** — to email the codes: https://resend.com (free tier). Verify a sending domain, or use
   `onboarding@resend.dev` for testing.
4. **Kit (ConvertKit)** — your newsletter. Create a **v4 API key** in Settings → Advanced → API.
   Optionally grab a **Form ID** to add subscribers to a form/sequence.

## Deploy
```bash
cd ~/RewriteApp-gateway
npm install
npx wrangler login

# Create the KV store, then paste the printed id into wrangler.toml (kv_namespaces.id)
npx wrangler kv namespace create RW_KV

# Set secrets (you'll be prompted to paste each value)
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put KIT_API_KEY
npx wrangler secret put TOKEN_SECRET     # any long random string

# Edit wrangler.toml [vars]: EMAIL_FROM (your verified sender), KIT_FORM_ID (optional),
# and the daily limits if you want.

npx wrangler deploy
```
Deploy prints your URL, e.g. `https://rewrite-gateway.<you>.workers.dev`.
**Put that URL into the app:** `RewriteApp/RewriteApp/GatewayConfig.swift` → `defaultBaseURL`
(or paste it in the app under Settings → Free models → Advanced).

## Local testing
```bash
cp .dev.vars.example .dev.vars   # fill in real values (gitignored)
npx wrangler dev
# then:
curl -X POST localhost:8787/auth/start  -H 'content-type: application/json' -d '{"email":"you@example.com"}'
curl -X POST localhost:8787/auth/verify -H 'content-type: application/json' -d '{"email":"you@example.com","code":"123456"}'
curl -X POST localhost:8787/v1/rewrite  -H "Authorization: Bearer <token>" -H 'content-type: application/json' \
     -d '{"systemPrompt":"Rewrite clearly.","text":"helo wrld"}'
```

## Config (wrangler.toml `[vars]`)
- `PROVIDER` — `gemini` (default) | `openrouter` | `groq` | `anthropic`. Switching providers needs only the
  matching secret (e.g. `OPENROUTER_API_KEY`) — **the app never changes.**
- `PER_USER_DAILY_LIMIT` (default 50), `GLOBAL_DAILY_LIMIT` (default 2000) — protect your quota.

## Honest notes
- Free tiers cap **daily** and are shared by all your users; keep this personal-scale. If it grows,
  flip `PROVIDER` to a cheap paid model (e.g. DeepSeek, or Anthropic Haiku) — one secret + one var.
- Google's free tier may use prompts to improve their models, and some free tiers restrict multi-user
  proxying in their ToS. The app's sign-in screen discloses that text is processed by the gateway + model.
