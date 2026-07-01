import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

type WebhookPayload = {
  type: "INSERT";
  table: "notifications";
  schema: "public";
  record: { id: string; user_id: string; title: string; body: string; url: string };
};

Deno.serve(async (request) => {
  try {
    const expectedSecret = Deno.env.get("WEBHOOK_SECRET");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const customSecretValid = expectedSecret && request.headers.get("x-webhook-secret") === expectedSecret;
    const serviceRoleValid = serviceRole && request.headers.get("authorization") === `Bearer ${serviceRole}`;
    if (!customSecretValid && !serviceRoleValid) {
      return Response.json({ error: "Non autorisé" }, { status: 401 });
    }
    const payload = await request.json() as WebhookPayload;
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT") || "mailto:bonjour@pacte.app",
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!
    );

    const { data: subscriptions, error } = await supabase
      .from("push_subscriptions")
      .select("id, subscription")
      .eq("user_id", payload.record.user_id);
    if (error) throw error;

    const message = JSON.stringify({
      title: payload.record.title,
      body: payload.record.body,
      url: payload.record.url || "/"
    });

    const results = await Promise.allSettled(
      (subscriptions || []).map(({ subscription }) => webpush.sendNotification(subscription, message))
    );

    return Response.json({
      delivered: results.filter(result => result.status === "fulfilled").length
    });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Erreur Push" }, { status: 500 });
  }
});
