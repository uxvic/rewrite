import type { Env } from "./model";

// Subscribes an email to Kit (ConvertKit). Uses the v4 API.
// Failure here is logged but NOT fatal to sign-in — we don't want a newsletter
// hiccup to block a user from using the app.
export async function subscribeToNewsletter(env: Env, email: string): Promise<void> {
  if (!env.KIT_API_KEY) return;
  try {
    // 1) Create/ensure the subscriber.
    const subRes = await fetch("https://api.kit.com/v4/subscribers", {
      method: "POST",
      headers: { "X-Kit-Api-Key": env.KIT_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ email_address: email }),
    });
    if (!subRes.ok) {
      console.log(`Kit subscriber ${subRes.status}: ${(await subRes.text()).slice(0, 200)}`);
    }

    // 2) Optionally add them to a form (so they enter your sequence).
    if (env.KIT_FORM_ID) {
      const formRes = await fetch(`https://api.kit.com/v4/forms/${env.KIT_FORM_ID}/subscribers`, {
        method: "POST",
        headers: { "X-Kit-Api-Key": env.KIT_API_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ email_address: email }),
      });
      if (!formRes.ok) {
        console.log(`Kit form ${formRes.status}: ${(await formRes.text()).slice(0, 200)}`);
      }
    }
  } catch (e) {
    console.log("Kit subscribe error:", (e as Error).message);
  }
}

// Unsubscribes an email from Kit when the user deletes their account.
// Non-fatal: a newsletter hiccup must not block account deletion.
export async function unsubscribeFromNewsletter(env: Env, email: string): Promise<void> {
  if (!env.KIT_API_KEY) return;
  try {
    const lookup = await fetch(
      `https://api.kit.com/v4/subscribers?email_address=${encodeURIComponent(email)}`,
      { headers: { "X-Kit-Api-Key": env.KIT_API_KEY } },
    );
    if (!lookup.ok) { console.log(`Kit lookup ${lookup.status}`); return; }
    const data = (await lookup.json()) as { subscribers?: Array<{ id: number }> };
    const id = data.subscribers?.[0]?.id;
    if (!id) return;
    const res = await fetch(`https://api.kit.com/v4/subscribers/${id}/unsubscribe`, {
      method: "POST",
      headers: { "X-Kit-Api-Key": env.KIT_API_KEY },
    });
    if (!res.ok) console.log(`Kit unsubscribe ${res.status}: ${(await res.text()).slice(0, 200)}`);
  } catch (e) {
    console.log("Kit unsubscribe error:", (e as Error).message);
  }
}
