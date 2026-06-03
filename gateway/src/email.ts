import type { Env } from "./model";

// Sends the 6-digit verification code via Resend.
export async function sendCodeEmail(env: Env, to: string, code: string): Promise<void> {
  const html = `
    <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:420px;margin:auto">
      <h2 style="letter-spacing:1px">REWRITE</h2>
      <p>Your sign-in code is:</p>
      <p style="font-size:30px;font-weight:700;letter-spacing:6px;background:#111;color:#CBFF2E;
                padding:14px;border-radius:8px;text-align:center">${code}</p>
      <p style="color:#666;font-size:13px">This code expires in 10 minutes. If you didn't request it, ignore this email.</p>
    </div>`;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: env.EMAIL_FROM,
      to: [to],
      subject: `Your Rewrite code: ${code}`,
      html,
    }),
  });
  if (!res.ok) {
    const msg = await res.text().catch(() => "");
    throw new Error(`Resend ${res.status}: ${msg.slice(0, 300)}`);
  }
}
