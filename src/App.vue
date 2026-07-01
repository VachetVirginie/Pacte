<script setup>
import { computed, onMounted, ref } from "vue";

const state = ref(null);
const loading = ref(true);
const error = ref("");
const checkinOpen = ref(false);
const postOpen = ref(false);
const note = ref("");
const postText = ref("");
const mood = ref("😎");
const toast = ref("");
const notificationsEnabled = ref(false);

const doneCount = computed(() => state.value?.members.filter(member => member.checkedIn).length ?? 0);
const currentMember = computed(() => state.value?.members.find(member => member.id === "vincent"));

function notify(message) {
  toast.value = message;
  setTimeout(() => { if (toast.value === message) toast.value = ""; }, 2800);
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json", ...options.headers },
    ...options
  });
  if (!response.ok) throw new Error((await response.json()).error || "Une erreur est survenue");
  return response.json();
}

async function load() {
  try {
    state.value = await api("/api/state");
  } catch (err) {
    error.value = "Impossible de joindre la bande pour le moment.";
  } finally {
    loading.value = false;
  }
}

async function checkin() {
  try {
    const result = await api("/api/checkins", {
      method: "POST",
      body: JSON.stringify({ memberId: "vincent", note: note.value, mood: mood.value })
    });
    currentMember.value.checkedIn = true;
    state.value.progress = result.progress;
    state.value.posts = result.posts;
    checkinOpen.value = false;
    notify("🔥 Check-in envoyé. La bande est au courant !");
  } catch (err) {
    notify(err.message);
  }
}

async function publishPost() {
  if (!postText.value.trim()) return;
  try {
    const post = await api("/api/posts", {
      method: "POST",
      body: JSON.stringify({ authorId: "vincent", body: postText.value })
    });
    state.value.posts.unshift(post);
    postText.value = "";
    postOpen.value = false;
    notify("Message publié dans le vestiaire.");
  } catch (err) {
    notify(err.message);
  }
}

async function react(post, emoji) {
  try {
    const updated = await api(`/api/posts/${post.id}/reactions`, {
      method: "POST", body: JSON.stringify({ emoji })
    });
    post.reactions = updated.reactions;
  } catch (err) {
    notify(err.message);
  }
}

async function nudge(member) {
  try {
    await api(`/api/nudges/${member.id}`, {
      method: "POST", body: JSON.stringify({ from: "Vincent" })
    });
    notify(`Petit coup de coude envoyé à ${member.name} 👀`);
  } catch (err) {
    notify(err.message);
  }
}

function urlBase64ToUint8Array(value) {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(base64), char => char.charCodeAt(0));
}

async function enableNotifications() {
  if (!("serviceWorker" in navigator) || !("Notification" in window)) {
    return notify("Les notifications ne sont pas compatibles avec ce navigateur.");
  }
  try {
    const permission = await Notification.requestPermission();
    if (permission !== "granted") return notify("Permission non accordée — aucun souci.");
    const registration = await navigator.serviceWorker.ready;
    if (state.value.vapidPublicKey) {
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(state.value.vapidPublicKey)
      });
      await api("/api/push/subscribe", {
        method: "POST", body: JSON.stringify(subscription)
      });
    }
    notificationsEnabled.value = true;
    registration.showNotification("Pacte est prêt 🔔", {
      body: "La bande pourra maintenant te faire signe.",
      icon: "/icon.svg"
    });
  } catch {
    notify("Impossible d'activer les notifications pour le moment.");
  }
}

function memberFor(post) {
  return state.value.members.find(member => member.id === post.authorId) ||
    { name: "La bande", initials: "PB", color: "green" };
}

onMounted(async () => {
  if ("serviceWorker" in navigator) await navigator.serviceWorker.register("/sw.js");
  notificationsEnabled.value = "Notification" in window && Notification.permission === "granted";
  await load();
});
</script>

<template>
  <main class="app-shell">
    <header class="topbar">
      <div class="brand"><span class="brand-mark">P</span><span>Pacte</span></div>
      <button class="avatar-button">VT</button>
    </header>

    <div v-if="loading" class="state-screen">La bande arrive…</div>
    <div v-else-if="error" class="state-screen">{{ error }}</div>

    <template v-else>
      <section class="greeting">
        <div><p class="eyebrow">MERCREDI 1 JUILLET</p><h1>Salut Vincent <span>👋</span></h1></div>
        <button class="icon-button" @click="enableNotifications" :aria-label="notificationsEnabled ? 'Notifications activées' : 'Activer les notifications'">
          {{ notificationsEnabled ? "🔔" : "🔕" }}<i v-if="!notificationsEnabled"></i>
        </button>
      </section>

      <section class="challenge-card">
        <div class="challenge-topline"><span class="live-pill"><i></i> EN COURS</span><button class="more-button">•••</button></div>
        <p class="challenge-kicker">{{ state.challenge.team.toUpperCase() }}</p>
        <h2>{{ state.challenge.title }}</h2>
        <p class="challenge-copy">{{ state.challenge.description }}</p>
        <div class="progress-head"><span>Progression collective</span><strong>{{ state.progress }}%</strong></div>
        <div class="progress-track"><div class="progress-fill" :style="{ width: `${state.progress}%` }"></div></div>
        <div class="challenge-meta"><span><b>{{ state.members.length }}</b> courageux</span><span><b>30</b> jours de défi</span></div>
        <div class="today-panel" :class="{ completed: currentMember.checkedIn }">
          <div class="today-copy"><span class="today-icon">✓</span><div><p>Aujourd'hui</p><strong>{{ currentMember.checkedIn ? "Mission accomplie. Cuisses officiellement en feu." : "Prêt à faire chauffer les cuisses ?" }}</strong></div></div>
          <button class="checkin-button" @click="currentMember.checkedIn ? notify('Déjà validé — tes quadriceps peuvent souffler.') : checkinOpen = true">
            {{ currentMember.checkedIn ? "Validé ✓" : "C'est fait !" }} <b v-if="!currentMember.checkedIn">+30</b>
          </button>
        </div>
      </section>

      <section class="squad-section">
        <div class="section-heading"><div><p class="eyebrow">LA BANDE</p><h3>{{ doneCount }} sur {{ state.members.length }} aujourd'hui</h3></div><span class="collective-badge">Presque !</span></div>
        <div class="squad">
          <button v-for="member in state.members" :key="member.id" class="member" @click="!member.checkedIn && member.id !== 'vincent' && nudge(member)">
            <div class="avatar" :class="member.color">{{ member.initials }}<span>{{ member.checkedIn ? "✓" : "!" }}</span></div><p>{{ member.name }}</p>
          </button>
        </div>
        <p class="nudge-copy">Touchez un retardataire pour lui envoyer un petit coup de coude.</p>
      </section>

      <section class="feed-section">
        <div class="section-heading feed-heading"><div><p class="eyebrow">LE VESTIAIRE</p><h3>Ça papote</h3></div><button class="text-button">Tout voir</button></div>
        <article v-for="post in state.posts" :key="post.id" class="post">
          <div class="post-avatar" :class="memberFor(post).color">{{ memberFor(post).initials }}</div>
          <div class="post-content">
            <div class="post-meta"><strong>{{ memberFor(post).name }}</strong><span>{{ post.time }}</span></div>
            <p>{{ post.body }}</p>
            <div class="post-actions">
              <button v-for="(count, emoji) in post.reactions" :key="emoji" class="reaction" @click="react(post, emoji)">{{ emoji }} <span>{{ count }}</span></button>
              <button class="reaction" @click="react(post, '👏')">👏</button>
            </div>
          </div>
        </article>
        <button class="new-post-button" @click="postOpen = true"><span>+</span> Partager un exploit, une plainte…</button>
      </section>

      <section class="reward-card">
        <div class="reward-icon">☕</div><div><p class="eyebrow">PROCHAIN PALIER</p><h3>{{ state.challenge.reward }} débloqué à {{ state.challenge.rewardAt }}%</h3><p>Encore un petit effort collectif.</p></div><strong>{{ state.progress }}%</strong>
      </section>
    </template>

    <nav class="bottom-nav">
      <button class="nav-item active"><span>⌂</span>Accueil</button><button class="nav-item"><span>⚡</span>Défis</button>
      <button class="central-action" @click="currentMember && !currentMember.checkedIn ? checkinOpen = true : notify('Défi déjà validé aujourd’hui.')">✓</button>
      <button class="nav-item"><span>♟</span>La bande</button><button class="nav-item"><span>☺</span>Profil</button>
    </nav>
  </main>

  <Transition name="toast"><div v-if="toast" class="toast">{{ toast }}</div></Transition>

  <div v-if="checkinOpen" class="modal-backdrop" @click.self="checkinOpen = false">
    <div class="dialog-card">
      <button type="button" class="dialog-close" @click="checkinOpen = false">×</button><div class="celebration">🔥</div>
      <p class="eyebrow">CHECK-IN DU JOUR</p><h2>Et 30 de plus !</h2><p>Tes cuisses te détestent peut-être, mais l'équipe est fière de toi.</p>
      <label>Un mot pour la bande ? <span>facultatif</span></label><textarea v-model="note" rows="3" placeholder="Facile. Enfin presque."></textarea>
      <div class="quick-reactions"><button v-for="item in [['😎','Facile'],['🥵','Ça pique'],['💀','Adieu']]" :key="item[0]" type="button" class="mood" :class="{ selected: mood === item[0] }" @click="mood = item[0]">{{ item[0] }} {{ item[1] }}</button></div>
      <button type="button" class="confirm-button" @click="checkin">Valider et fanfaronner</button>
    </div>
  </div>

  <div v-if="postOpen" class="modal-backdrop" @click.self="postOpen = false">
    <div class="dialog-card">
      <button type="button" class="dialog-close" @click="postOpen = false">×</button><p class="eyebrow">LE VESTIAIRE</p><h2>Raconte-nous tout</h2>
      <textarea v-model="postText" rows="5" placeholder="Un exploit, une excuse créative…"></textarea><button type="button" class="confirm-button" @click="publishPost">Publier</button>
    </div>
  </div>
</template>
