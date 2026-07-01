import express from "express";
import webpush from "web-push";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readStore, updateStore } from "./store.js";

const app = express();
const port = Number(process.env.PORT || 3001);
const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, "../dist");
const vapidPublicKey = process.env.VAPID_PUBLIC_KEY;
const vapidPrivateKey = process.env.VAPID_PRIVATE_KEY;

if (vapidPublicKey && vapidPrivateKey) {
  webpush.setVapidDetails(
    process.env.VAPID_SUBJECT || "mailto:bonjour@pacte.app",
    vapidPublicKey,
    vapidPrivateKey
  );
}

app.use(express.json());

app.get("/api/state", async (_req, res) => {
  const data = await readStore();
  const { subscriptions, ...publicData } = data;
  res.json({ ...publicData, vapidPublicKey: vapidPublicKey || null });
});

app.post("/api/checkins", async (req, res) => {
  const memberId = req.body.memberId || "vincent";
  const result = await updateStore((data) => {
    const member = data.members.find((item) => item.id === memberId);
    if (!member) return null;
    if (member.checkedIn) {
      return { member, progress: data.progress, posts: data.posts, alreadyDone: true };
    }
    member.checkedIn = true;
    member.checkedInAt = new Date().toISOString();
    data.progress = Math.min(100, data.progress + 2);
    if (req.body.note?.trim()) {
      data.posts.unshift({
        id: Date.now(),
        authorId: memberId,
        body: req.body.note.trim(),
        time: "à l'instant",
        reactions: { [req.body.mood || "🔥"]: 0 }
      });
    }
    return { member, progress: data.progress, posts: data.posts };
  });
  if (!result) return res.status(404).json({ error: "Membre introuvable" });
  res.status(201).json(result);
});

app.post("/api/posts", async (req, res) => {
  if (!req.body.body?.trim()) return res.status(400).json({ error: "Message vide" });
  const post = {
    id: Date.now(),
    authorId: req.body.authorId || "vincent",
    body: req.body.body.trim(),
    time: "à l'instant",
    reactions: {}
  };
  await updateStore((data) => data.posts.unshift(post));
  res.status(201).json(post);
});

app.post("/api/posts/:id/reactions", async (req, res) => {
  const result = await updateStore((data) => {
    const post = data.posts.find((item) => String(item.id) === req.params.id);
    if (!post) return null;
    const emoji = req.body.emoji;
    post.reactions[emoji] = (post.reactions[emoji] || 0) + 1;
    return post;
  });
  if (!result) return res.status(404).json({ error: "Message introuvable" });
  res.json(result);
});

app.post("/api/push/subscribe", async (req, res) => {
  if (!req.body?.endpoint) return res.status(400).json({ error: "Abonnement invalide" });
  await updateStore((data) => {
    if (!data.subscriptions.some((item) => item.endpoint === req.body.endpoint)) {
      data.subscriptions.push(req.body);
    }
  });
  res.status(201).json({ ok: true });
});

app.post("/api/nudges/:memberId", async (req, res) => {
  const data = await readStore();
  const member = data.members.find((item) => item.id === req.params.memberId);
  if (!member) return res.status(404).json({ error: "Membre introuvable" });
  if (!vapidPublicKey || !vapidPrivateKey) {
    return res.json({ ok: true, demo: true, message: `Relance enregistrée pour ${member.name}` });
  }
  const payload = JSON.stringify({
    title: "Petit coup de coude 👀",
    body: `${req.body.from || "La bande"} t'attend pour le défi du jour.`,
    url: "/"
  });
  const outcomes = await Promise.allSettled(
    data.subscriptions.map((subscription) => webpush.sendNotification(subscription, payload))
  );
  res.json({ ok: true, delivered: outcomes.filter((item) => item.status === "fulfilled").length });
});

app.use(express.static(dist));
app.get("/{*splat}", (_req, res) => res.sendFile(join(dist, "index.html")));

app.listen(port, "127.0.0.1", () => {
  console.log(`Pacte API disponible sur http://127.0.0.1:${port}`);
  if (!vapidPublicKey) console.log("Web Push en mode démo : ajoutez les clés VAPID pour l'envoi réel.");
});
