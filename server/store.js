import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dataFile = join(here, "data.json");

const initialData = {
  challenge: {
    id: "squats-juillet",
    team: "L'équipe des mollets",
    title: "30 squats par jour",
    description: "Un mois pour transformer nos pauses café en cuisses d'acier.",
    dailyTarget: 30,
    endDate: "2026-07-31",
    reward: "Café-croissants",
    rewardAt: 80
  },
  members: [
    { id: "amelie", name: "Amélie", initials: "AM", checkedIn: true, color: "coral" },
    { id: "julien", name: "Julien", initials: "JL", checkedIn: true, color: "blue" },
    { id: "sarah", name: "Sarah", initials: "SK", checkedIn: true, color: "yellow" },
    { id: "vincent", name: "Vous", initials: "VT", checkedIn: false, color: "green" },
    { id: "thomas", name: "Thomas", initials: "TM", checkedIn: false, color: "stone" }
  ],
  progress: 72,
  posts: [
    { id: 1, authorId: "amelie", body: "30 squats entre deux réunions. Mon professionnalisme n'a désormais plus aucune limite.", time: "il y a 12 min", reactions: { "🔥": 3, "💪": 1 } },
    { id: 2, authorId: "julien", body: "J'ai entendu mes genoux négocier une rupture conventionnelle.", time: "il y a 1 h", reactions: { "😂": 4, "🫡": 2 } }
  ],
  subscriptions: []
};

async function ensureStore() {
  await mkdir(here, { recursive: true });
  try {
    await readFile(dataFile, "utf8");
  } catch {
    await writeFile(dataFile, JSON.stringify(initialData, null, 2));
  }
}

export async function readStore() {
  await ensureStore();
  return JSON.parse(await readFile(dataFile, "utf8"));
}

export async function updateStore(mutator) {
  const data = await readStore();
  const result = await mutator(data);
  await writeFile(dataFile, JSON.stringify(data, null, 2));
  return result ?? data;
}
