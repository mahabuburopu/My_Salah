// Supabase Edge Function: send-otp
// Deploy with: supabase functions deploy send-otp
//
// Required secrets (set once via Supabase CLI):
//   supabase secrets set BREVO_API_KEY=your_key_here
//   supabase secrets set BREVO_SENDER_EMAIL=noreply@yourdomain.com
//   supabase secrets set BREVO_SENDER_NAME="My Salah App"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Helper to build a JSON response
function jsonResponse(
  body: unknown,
  status: number = 200
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Helper to compute SHA-256 hex string
async function sha256Hex(text: string): Promise<string> {
  const buffer = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text)
  );
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json() as {
      action?: string;
      email?: string;
      otp?: string;
    };

    const action = body.action ?? "";
    const email = (body.email ?? "").trim().toLowerCase();
    const otp = (body.otp ?? "").trim();

    if (!email) {
      return jsonResponse({ success: false, error: "Email is required" }, 400);
    }

    // Supabase client with service role key (bypasses RLS for OTP table)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ── ACTION: send ─────────────────────────────────────────────────────────
    if (action === "send") {
      // 1. Generate 6-digit OTP
      const rawOtp = Math.floor(100000 + Math.random() * 900000).toString();

      // 2. Hash it — never store raw OTPs
      const otpHash = await sha256Hex(rawOtp);

      // 3. Store with 10-minute expiry
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      const { error: insertError } = await supabase
        .from("otp_verifications")
        .insert({ email, otp_hash: otpHash, expires_at: expiresAt });

      if (insertError) {
        console.error("DB insert error:", insertError.message);
        return jsonResponse({ success: false, error: "Failed to store OTP. Please try again." }, 500);
      }

      // 4. Send via Brevo Transactional Email API
      const brevoRes = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
          "api-key": Deno.env.get("BREVO_API_KEY") ?? "",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify({
          sender: {
            name: Deno.env.get("BREVO_SENDER_NAME") ?? "My Salah App",
            email: Deno.env.get("BREVO_SENDER_EMAIL") ?? "",
          },
          to: [{ email }],
          subject: "Your My Salah Verification Code",
          htmlContent: `
            <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;background:#1a1008;color:#fff;border-radius:16px;padding:32px;">
              <div style="text-align:center;margin-bottom:24px;">
                <h1 style="color:#D4A96A;font-size:28px;margin:0;">My Salah</h1>
                <p style="color:#A08060;font-size:14px;margin-top:4px;">Email Verification</p>
              </div>
              <p style="font-size:16px;color:#e0d4c0;">Your one-time verification code is:</p>
              <div style="background:#2C1F11;border:1.5px solid #D4A96A;border-radius:12px;padding:20px;text-align:center;margin:20px 0;">
                <span style="font-size:40px;font-weight:bold;color:#D4A96A;letter-spacing:12px;">${rawOtp}</span>
              </div>
              <p style="color:#A08060;font-size:13px;text-align:center;">
                This code expires in <strong style="color:#D4A96A;">10 minutes</strong>.
              </p>
              <p style="color:#A08060;font-size:12px;text-align:center;margin-top:24px;">
                If you did not request this, please ignore this email.
              </p>
            </div>
          `,
        }),
      });

      if (!brevoRes.ok) {
        const errBody = await brevoRes.text();
        console.error("Brevo error:", brevoRes.status, errBody);
        return jsonResponse(
          { success: false, error: "Failed to send email. Check your Brevo API key." },
          500
        );
      }

      return jsonResponse({ success: true });
    }

    // ── ACTION: verify ───────────────────────────────────────────────────────
    if (action === "verify") {
      if (!otp) {
        return jsonResponse({ success: false, error: "OTP is required" }, 400);
      }

      // 1. Hash the submitted OTP
      const otpHash = await sha256Hex(otp);

      // 2. Look up a matching, unused, non-expired record
      const { data, error: dbError } = await supabase
        .from("otp_verifications")
        .select("id")
        .eq("email", email)
        .eq("otp_hash", otpHash)
        .eq("used", false)
        .gt("expires_at", new Date().toISOString())
        .maybeSingle();

      if (dbError || !data) {
        return jsonResponse(
          { success: false, error: "Invalid or expired OTP. Please try again." },
          400
        );
      }

      // 3. Mark as used to prevent replay attacks
      await supabase
        .from("otp_verifications")
        .update({ used: true })
        .eq("id", (data as { id: number }).id);

      return jsonResponse({ success: true });
    }

    // Unknown action
    return jsonResponse(
      { success: false, error: "Invalid action. Use 'send' or 'verify'." },
      400
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("Edge Function error:", message);
    return jsonResponse({ success: false, error: "Internal server error." }, 500);
  }
});
