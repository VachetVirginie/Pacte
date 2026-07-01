<script setup>
import { computed, onMounted, onUnmounted, ref } from "vue";
import { pacte } from "./services/pacte";

const state = ref(null);
const loading = ref(true);
const saving = ref(false);
const error = ref("");
const checkinOpen = ref(false);
const postOpen = ref(false);
const challengeOpen = ref(false);
const activeView = ref("home");
const note = ref("");
const postText = ref("");
const mood = ref("😎");
const toast = ref("");
const notificationsEnabled = ref(false);
const onboardingMode = ref("create");
const teamName = ref("L'équipe des mollets");
const memberName = ref("");
const inviteCode = ref("");
const challengeTitle = ref("");
const challengeDescription = ref("");
const challengeTarget = ref(30);
const challengeTargetMode = ref("fixed");
const challengeIncrement = ref(5);
const challengeDuration = ref(30);
const challengeReward = ref("");
const challengeRewardAt = ref(80);
const checkinChallengeId = ref(null);
const bonusTargetOpen = ref(false);
const joinTeamOpen = ref(false);
const joinTeamCode = ref("");
const joinTeamName = ref("");
const updateReady = ref(false);
const reactionOptions = ["🔥", "👏", "😂", "💪", "❤️", "😮"];
let unsubscribe = () => {};

const doneCount = computed(() => state.value?.challenge?.doneCount ?? state.value?.members?.filter(member => member.checkedIn).length ?? 0);
const currentMember = computed(() => state.value?.members?.find(member => member.id === state.value.currentUserId));
const checkinChallenge = computed(() =>
  state.value?.challenges?.find(challenge => challenge.id === checkinChallengeId.value) ||
  state.value?.challenge
);
const activeBonus = computed(() => state.value?.ownedCards?.[0] || state.value?.receivedCards?.[0] || null);
const today = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" }).format(new Date()).toUpperCase();

function notify(message) {
  toast.value = message;
  setTimeout(() => { if (toast.value === message) toast.value = ""; }, 2800);
}

function reloadPage() {
  location.reload();
}

async function load(silent = false) {
  if (!silent) loading.value = true;
  try {
    state.value = await pacte.initialize();
    error.value = "";
  } catch (err) {
    error.value = err.message || "Impossible de joindre la bande pour le moment.";
  } finally {
    loading.value = false;
  }
}

async function finishOnboarding() {
  if (!memberName.value.trim()) return notify("Dis-nous d'abord comment t'appeler.");
  if (onboardingMode.value === "join" && !inviteCode.value.trim()) return notify("Il manque le code d'invitation.");
  saving.value = true;
  try {
    state.value = onboardingMode.value === "create"
      ? await pacte.createTeam(teamName.value.trim() || "Ma bande", memberName.value.trim())
      : await pacte.joinTeam(inviteCode.value.trim(), memberName.value.trim());
    unsubscribe = pacte.subscribe(() => refresh());
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

async function createChallenge() {
  if (!challengeTitle.value.trim()) return notify("Donne un nom à ton challenge.");
  if (Number(challengeTarget.value) < 1) return notify("L’objectif quotidien doit être supérieur à zéro.");
  saving.value = true;
  try {
    state.value = await pacte.createChallenge({
      title: challengeTitle.value.trim(),
      description: challengeDescription.value.trim(),
      dailyTarget: challengeTarget.value,
      targetMode: challengeTargetMode.value,
      dailyIncrement: challengeTargetMode.value === "linear" ? challengeIncrement.value : 0,
      durationDays: challengeDuration.value,
      reward: challengeReward.value.trim(),
      rewardAt: challengeRewardAt.value
    });
    challengeOpen.value = false;
    notify("⚡ Challenge lancé. La bande n’a plus d’excuse !");
    unsubscribe();
    unsubscribe = pacte.subscribe(() => refresh());
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

function cancelChallengeBuilder() {
  state.value.challengeOnboarding = false;
  state.value.onboarding = true;
}

async function refresh() {
  try { state.value = await pacte.load(); } catch { /* prochaine reconnexion */ }
}

async function checkin() {
  saving.value = true;
  try {
    state.value = await pacte.checkin(checkinChallenge.value.id, note.value, mood.value);
    note.value = "";
    checkinOpen.value = false;
    notify("🔥 Check-in envoyé. La bande est au courant !");
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

function openCheckin(challenge = state.value.challenge) {
  if (challenge.checkedIn) return notify("Ce challenge est déjà validé aujourd’hui.");
  checkinChallengeId.value = challenge.id;
  checkinOpen.value = true;
}

async function selectChallenge(challenge) {
  saving.value = true;
  try {
    state.value.challenge = challenge;
    state.value.progress = challenge.progress;
    const checkedIds = challenge.checkedMemberIds || [];
    state.value.members = state.value.members.map(member => ({
      ...member,
      checkedIn: checkedIds.includes(member.id)
    }));
    state.value.posts = await pacte.getWallPosts(challenge.id);
    activeView.value = "home";
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

async function confirmDelete(challenge) {
  if (!confirm(`Supprimer "${challenge.title}" ? Les checkins seront perdus, les membres restent.`)) return;
  saving.value = true;
  try {
    state.value = await pacte.deleteChallenge(challenge.id);
    notify("Challenge supprimé.");
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

function openJoinTeam() {
  joinTeamCode.value = "";
  joinTeamName.value = currentMember.value?.name || "";
  joinTeamOpen.value = true;
}

async function confirmJoinTeam() {
  if (!joinTeamCode.value.trim()) return notify("Il manque le code d’invitation.");
  if (!joinTeamName.value.trim()) return notify("Dis-nous comment t’appeler.");
  saving.value = true;
  try {
    state.value = await pacte.joinTeam(joinTeamCode.value.trim(), joinTeamName.value.trim());
    joinTeamOpen.value = false;
    notify("Tu as rejoint la nouvelle équipe !");
    unsubscribe();
    unsubscribe = pacte.subscribe(() => refresh());
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

async function selectTeam(team) {
  saving.value = true;
  try {
    state.value = await pacte.selectTeam(team.id);
    activeView.value = "home";
    notify(`Équipe ${team.name} sélectionnée.`);
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

async function publishPost() {
  if (!postText.value.trim()) return;
  saving.value = true;
  try {
    state.value = await pacte.publishPost(postText.value.trim(), state.value.challenge?.id);
    postText.value = "";
    postOpen.value = false;
    notify("Message publié dans le vestiaire.");
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

async function react(post, emoji) {
  try { state.value = await pacte.react(post.id, emoji); }
  catch (err) { notify(err.message); }
}

async function assignBonus(targetMemberId = null) {
  if (!activeBonus.value) return;
  saving.value = true;
  try {
    state.value = await pacte.assignBonus(activeBonus.value.id, targetMemberId);
    bonusTargetOpen.value = false;
    notify("💥 Carte jouée. Le mur est déjà au courant !");
  } catch (err) {
    notify(err.message);
  } finally {
    saving.value = false;
  }
}

async function acknowledgeBonus() {
  if (!activeBonus.value) return;
  try {
    state.value = await pacte.acknowledgeBonus(activeBonus.value.id);
    notify("Carte encaissée. Courage.");
  } catch (err) {
    notify(err.message);
  }
}

async function nudge(member) {
  try {
    await pacte.nudge(member.id);
    notify(`Petit coup de coude envoyé à ${member.name} 👀`);
  } catch (err) {
    notify(err.message);
  }
}

async function copyInvite() {
  await navigator.clipboard.writeText(state.value.inviteCode);
  notify(`Code ${state.value.inviteCode} copié !`);
}

async function shareInvite() {
  const code = state.value.inviteCode;
  const url = `${window.location.origin}/?invite=${encodeURIComponent(code)}`;
  const shareData = {
    title: "Rejoins notre équipe sur Pacte",
    text: `Notre code d’invitation est ${code}. Prêt·e à relever le défi ?`,
    url
  };
  if (navigator.share) {
    try {
      await navigator.share(shareData);
      return;
    } catch (err) {
      if (err?.name === "AbortError") return;
    }
  }
  await navigator.clipboard.writeText(`${shareData.text}\n${url}`);
  notify("Lien d’invitation copié !");
}

function urlBase64ToUint8Array(value) {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(base64), char => char.charCodeAt(0));
}

async function enableNotifications() {
  const publicKey = import.meta.env.VITE_VAPID_PUBLIC_KEY;
  if (!("serviceWorker" in navigator) || !("Notification" in window)) return notify("Notifications non compatibles avec ce navigateur.");
  if (!publicKey && pacte.isLive) return notify("Ajoutez VITE_VAPID_PUBLIC_KEY pour activer le Push.");
  try {
    const permission = await Notification.requestPermission();
    if (permission !== "granted") return notify("Permission non accordée — aucun souci.");
    const registration = await navigator.serviceWorker.ready;
    if (publicKey) {
      const existing = await registration.pushManager.getSubscription();
      const subscription = existing || await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey)
      });
      await pacte.savePushSubscription(subscription);
    }
    notificationsEnabled.value = true;
    await registration.showNotification("Pacte est prêt 🔔", { body: "La bande pourra maintenant te faire signe.", icon: "/icon.svg" });
  } catch {
    notify("Impossible d'activer les notifications pour le moment.");
  }
}

function memberFor(post) {
  return state.value.members.find(member => member.id === post.authorId) ||
    { name: "La bande", initials: "PB", color: "green" };
}

onMounted(async () => {
  const invitedWith = new URLSearchParams(window.location.search).get("invite");
  if (invitedWith) {
    onboardingMode.value = "join";
    inviteCode.value = invitedWith.toUpperCase();
  }
  if ("serviceWorker" in navigator) {
    const registration = await navigator.serviceWorker.register("/sw.js");
    registration.addEventListener("updatefound", () => {
      const worker = registration.installing;
      if (!worker) return;
      worker.addEventListener("statechange", () => {
        if (worker.state === "installed" && navigator.serviceWorker.controller) {
          updateReady.value = true;
        }
      });
    });
  }
  notificationsEnabled.value = "Notification" in window && Notification.permission === "granted";
  await load();
  if (state.value && !state.value.onboarding) unsubscribe = pacte.subscribe(() => refresh());
});

onUnmounted(() => unsubscribe());
</script>

<template>
  <main class="app-shell">
    <div v-if="updateReady" class="update-banner">
      <span>Nouvelle version disponible</span>
      <button @click="reloadPage">Mettre à jour</button>
    </div>
    <header class="topbar">
      <div class="brand"><span class="brand-mark">P</span><span>Pacte</span></div>
      <span v-if="state?.mode === 'demo'" class="demo-pill">MODE DÉMO</span>
      <button v-else-if="currentMember" class="avatar-button">{{ currentMember.initials }}</button>
    </header>

    <div v-if="loading" class="state-screen">La bande arrive…</div>
    <div v-else-if="error" class="state-screen error-state"><strong>Petit pépin technique</strong><p>{{ error }}</p><button class="confirm-button" @click="load()">Réessayer</button></div>

    <section v-else-if="state?.onboarding" class="onboarding-card">
      <span class="onboarding-emoji">🤝</span>
      <p class="eyebrow">BIENVENUE DANS PACTE</p>
      <h1>On monte une bande ?</h1>
      <p>Crée ton équipe ou rejoins tes collègues avec leur code d’invitation.</p>
      <div class="onboarding-tabs">
        <button :class="{ active: onboardingMode === 'create' }" @click="onboardingMode = 'create'">Créer une équipe</button>
        <button :class="{ active: onboardingMode === 'join' }" @click="onboardingMode = 'join'">J’ai un code</button>
      </div>
      <label>Ton prénom</label>
      <input v-model="memberName" placeholder="Camille" maxlength="40">
      <template v-if="onboardingMode === 'create'">
        <label>Nom de l’équipe</label>
        <input v-model="teamName" placeholder="Les mollets vaillants" maxlength="60">
      </template>
      <template v-else>
        <label>Code d’invitation</label>
        <input v-model="inviteCode" class="code-input" placeholder="MOLLETS" maxlength="8">
        <p class="reconnect-hint">Déjà membre ? Remets exactement le même pseudo : tu retrouveras ton profil et ton historique.</p>
      </template>
      <button class="confirm-button" :disabled="saving" @click="finishOnboarding">{{ saving ? "Une seconde…" : onboardingMode === "create" ? "Créer notre Pacte" : "Rejoindre la bande" }}</button>
    </section>

    <section v-else-if="state?.challengeOnboarding" class="onboarding-card challenge-builder">
      <button class="text-button" @click="cancelChallengeBuilder">← Retour</button>
      <span class="onboarding-emoji">⚡</span>
      <p class="eyebrow">{{ state.teamName?.toUpperCase() }}</p>
      <h1>Quel défi on se lance ?</h1>
      <p>Le nom de l’équipe, c’était l’échauffement. Maintenant, définis les règles du jeu.</p>
      <div class="invite-box">
        <div><span>CODE D’ÉQUIPE</span><strong>{{ state.inviteCode }}</strong></div>
        <button @click="shareInvite">Inviter quelqu’un</button>
      </div>
      <label>Nom du challenge</label>
      <input v-model="challengeTitle" placeholder="30 squats par jour" maxlength="80">
      <label>Description <span>facultatif</span></label>
      <textarea v-model="challengeDescription" rows="3" placeholder="Un mois pour devenir la terreur des escaliers…"></textarea>
      <label>Évolution de l’objectif</label>
      <div class="progression-toggle">
        <button :class="{ active: challengeTargetMode === 'fixed' }" @click="challengeTargetMode = 'fixed'">Objectif fixe</button>
        <button :class="{ active: challengeTargetMode === 'linear' }" @click="challengeTargetMode = 'linear'">Progressif</button>
      </div>
      <div class="form-grid">
        <div><label>{{ challengeTargetMode === "linear" ? "Objectif jour 1" : "Objectif quotidien" }}</label><input v-model.number="challengeTarget" type="number" min="1" max="10000"></div>
        <div v-if="challengeTargetMode === 'linear'"><label>+ chaque jour</label><input v-model.number="challengeIncrement" type="number" min="0" max="10000"></div>
        <div><label>Durée</label><select v-model.number="challengeDuration"><option :value="7">7 jours</option><option :value="14">14 jours</option><option :value="21">21 jours</option><option :value="30">30 jours</option><option :value="60">60 jours</option></select></div>
      </div>
      <p v-if="challengeTargetMode === 'linear'" class="progression-preview">Jour 1 : <b>{{ challengeTarget }}</b> · Jour 2 : <b>{{ Number(challengeTarget) + Number(challengeIncrement) }}</b> · Jour 3 : <b>{{ Number(challengeTarget) + Number(challengeIncrement) * 2 }}</b></p>
      <label>Récompense collective <span>facultatif</span></label>
      <input v-model="challengeReward" placeholder="Café-croissants, déjeuner d’équipe…" maxlength="80">
      <label>Palier de déblocage</label>
      <div class="range-row"><input v-model.number="challengeRewardAt" type="range" min="50" max="100" step="5"><strong>{{ challengeRewardAt }}%</strong></div>
      <button class="confirm-button" :disabled="saving" @click="createChallenge">{{ saving ? "Lancement…" : "Lancer le challenge" }}</button>
    </section>

    <template v-else-if="activeView === 'home'">
      <section class="greeting">
        <div><p class="eyebrow">{{ today }}</p><h1>Salut {{ currentMember.name }} <span>👋</span></h1></div>
        <button class="icon-button" @click="enableNotifications" :aria-label="notificationsEnabled ? 'Notifications activées' : 'Activer les notifications'">
          {{ notificationsEnabled ? "🔔" : "🔕" }}<i v-if="!notificationsEnabled"></i>
        </button>
      </section>

      <section class="challenge-card">
        <div class="challenge-topline"><span class="live-pill"><i></i> EN COURS</span><button class="more-button" aria-label="Créer un nouveau challenge" @click="challengeOpen = true">＋</button></div>
        <p class="challenge-kicker">{{ state.challenge.team.toUpperCase() }}</p>
        <h2>{{ state.challenge.title }}</h2>
        <p class="challenge-copy">{{ state.challenge.description }}</p>
        <p v-if="state.challenge.targetMode === 'linear'" class="day-target">Jour {{ state.challenge.dayNumber }} · objectif du jour : <b>{{ state.challenge.todayTarget }}</b></p>
        <p v-if="state.challenge.activeEffects?.length" class="bonus-effect-pill">{{ state.challenge.activeEffects[0].emoji }} {{ state.challenge.activeEffects[0].title }} actif · objectif initial {{ state.challenge.baseTodayTarget }}</p>
        <div class="progress-head"><span>Progression collective</span><strong>{{ state.progress }}%</strong></div>
        <div class="progress-track"><div class="progress-fill" :style="{ width: `${state.progress}%` }"></div></div>
        <div class="challenge-meta"><span><b>{{ state.members.length }}</b> courageux</span><button class="invite-chip" @click="shareInvite">Inviter · {{ state.inviteCode }}</button></div>
        <div class="today-panel" :class="{ completed: state.challenge.checkedIn }">
          <div class="today-copy"><span class="today-icon">✓</span><div><p>Aujourd'hui · objectif {{ state.challenge.todayTarget || state.challenge.dailyTarget }}</p><strong>{{ state.challenge.checkedIn ? "Mission accomplie. La bande valide." : "Prêt à relever le défi ?" }}</strong></div></div>
          <button class="checkin-button" @click="openCheckin(state.challenge)">
            {{ state.challenge.checkedIn ? "Validé ✓" : "C'est fait !" }} <b v-if="!state.challenge.checkedIn">+{{ state.challenge.todayTarget || state.challenge.dailyTarget }}</b>
          </button>
        </div>
      </section>

      <section class="squad-section">
        <div class="section-heading"><div><p class="eyebrow">LA BANDE</p><h3>{{ doneCount }} sur {{ state.members.length }} aujourd'hui</h3></div><span class="collective-badge">Presque !</span></div>
        <div class="squad">
          <button v-for="member in state.members" :key="member.id" class="member" @click="!member.checkedIn && member.id !== state.currentUserId && nudge(member)">
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
              <button v-for="emoji in reactionOptions" :key="emoji" class="reaction" :class="{ active: post.reactionPeople?.[emoji]?.includes(currentMember.name) }" @click="react(post, emoji)">{{ emoji }} <span v-if="post.reactions?.[emoji]">{{ post.reactions[emoji] }}</span></button>
            </div>
            <div v-if="Object.keys(post.reactionPeople || {}).length" class="reaction-people">
              <span v-for="(people, emoji) in post.reactionPeople" :key="emoji">{{ emoji }} {{ people.join(", ") }}</span>
            </div>
          </div>
        </article>
        <button class="new-post-button" @click="postOpen = true"><span>+</span> Partager un exploit, une plainte…</button>
      </section>

      <section class="reward-card">
        <div class="reward-icon">☕</div><div><p class="eyebrow">PROCHAIN PALIER</p><h3>{{ state.challenge.reward }} débloqué à {{ state.challenge.rewardAt }}%</h3><p>Encore un petit effort collectif.</p></div><strong>{{ state.progress }}%</strong>
      </section>
    </template>

    <section v-else-if="activeView === 'challenges'" class="page-view">
      <div class="page-title"><div><p class="eyebrow">LES DÉFIS</p><h1>À nous de jouer</h1></div><div class="page-actions"><button class="text-button" @click="openJoinTeam">Rejoindre une équipe</button><button class="round-add" @click="challengeOpen = true">＋</button></div></div>
      <p class="page-intro">{{ state.challenges?.length || 1 }} challenge{{ (state.challenges?.length || 1) > 1 ? "s" : "" }} en cours — choisis ton terrain de jeu.</p>
      <div v-if="state.teams?.length > 1" class="teams-list compact">
        <p class="eyebrow">MES ÉQUIPES</p>
        <article v-for="team in state.teams" :key="team.id" class="team-row" :class="{ active: team.id === state.teamId }" @click="selectTeam(team)">
          <div><strong>{{ team.name }}</strong><small>{{ team.memberCount }} membres</small></div>
          <span v-if="team.id === state.teamId">ACTIF</span>
        </article>
      </div>
      <article v-for="challenge in state.challenges || [state.challenge]" :key="challenge.id" class="detail-card active-challenge challenge-list-item">
        <div class="card-status"><span class="live-pill" :class="{ active: challenge.id === state.challenge?.id }"><i></i>{{ challenge.id === state.challenge?.id ? "ACTIF" : "EN COURS" }}</span><strong>{{ challenge.progress }}%</strong></div>
        <p class="eyebrow">{{ challenge.targetMode === "linear" ? `PROGRESSIF · JOUR ${challenge.dayNumber}` : "OBJECTIF FIXE" }}</p>
        <h2>{{ challenge.title }}</h2>
        <p>{{ challenge.description || "La règle est simple : on s’y tient ensemble." }}</p>
        <div class="metric-grid">
          <div><strong>{{ challenge.todayTarget || challenge.dailyTarget }}</strong><span>objectif du jour</span></div>
          <div><strong>{{ challenge.durationDays || 30 }}</strong><span>jours</span></div>
          <div><strong>{{ challenge.doneCount }}/{{ state.members.length }}</strong><span>aujourd’hui</span></div>
        </div>
        <button class="text-button" style="color:var(--coral);margin:4px 0 10px" @click="confirmDelete(challenge)">Supprimer ce challenge</button>
        <div class="challenge-card-actions"><button class="secondary-button" @click="selectChallenge(challenge)">Voir</button><button class="confirm-button" @click="openCheckin(challenge)">{{ challenge.checkedIn ? "Validé ✓" : "Valider" }}</button></div>
      </article>
      <button class="outline-action" @click="challengeOpen = true">⚡ Lancer un nouveau challenge</button>
      <div class="empty-history"><span>🏁</span><strong>Historique à venir</strong><p>Les défis terminés apparaîtront ici, avec les meilleurs moments de la bande.</p></div>
    </section>

    <section v-else-if="activeView === 'squad'" class="page-view">
      <div class="page-title"><div><p class="eyebrow">LA BANDE</p><h1>{{ state.challenge.team }}</h1></div><span class="member-count">{{ state.members.length }}</span></div>
      <div class="invite-box large-invite">
        <div><span>CODE D’ÉQUIPE</span><strong>{{ state.inviteCode }}</strong><small>À partager avec tes collègues</small></div>
        <button @click="shareInvite">Inviter</button>
      </div>
      <div class="member-list">
        <article v-for="member in state.members" :key="member.id" class="member-row">
          <div class="avatar" :class="member.color">{{ member.initials }}<span>{{ member.checkedIn ? "✓" : "!" }}</span></div>
          <div><strong>{{ member.name }}</strong><p>{{ member.id === state.currentUserId ? "C’est toi" : member.checkedIn ? "Défi validé aujourd’hui" : "Pas encore passé·e à l’action" }}</p></div>
          <button v-if="!member.checkedIn && member.id !== state.currentUserId" @click="nudge(member)">👀 Relancer</button>
        </article>
      </div>
    </section>

    <section v-else-if="activeView === 'profile'" class="page-view">
      <div class="page-title"><div><p class="eyebrow">MON PROFIL</p><h1>Ton coin à toi</h1></div></div>
      <div class="profile-card">
        <div class="profile-avatar" :class="currentMember.color">{{ currentMember.initials }}</div>
        <h2>{{ currentMember.name }}</h2>
        <p>{{ state.challenge.team }}</p>
        <span>{{ state.challenges?.filter(item => item.checkedIn).length || 0 }}/{{ state.challenges?.length || 1 }} challenges validés aujourd’hui</span>
      </div>
      <div class="settings-list">
        <button @click="enableNotifications"><span>🔔</span><div><strong>Notifications</strong><small>{{ notificationsEnabled ? "Activées" : "Appuie pour les activer" }}</small></div><b>›</b></button>
        <button @click="shareInvite"><span>🤝</span><div><strong>Inviter un collègue</strong><small>Code {{ state.inviteCode }}</small></div><b>›</b></button>
        <button @click="notify('Pacte est déjà installable depuis le menu du navigateur.')"><span>📲</span><div><strong>Installer l’application</strong><small>Ajouter à l’écran d’accueil</small></div><b>›</b></button>
      </div>
      <div v-if="state.teams?.length > 1" class="teams-list">
        <p class="eyebrow">MES ÉQUIPES</p>
        <article v-for="team in state.teams" :key="team.id" class="team-row" :class="{ active: team.id === state.teamId }" @click="selectTeam(team)">
          <div><strong>{{ team.name }}</strong><small>{{ team.memberCount }} membres · code {{ team.inviteCode }}</small></div>
          <span v-if="team.id === state.teamId">ACTIF</span>
        </article>
      </div>
      <p class="privacy-note">Pacte ne mesure pas tes mouvements et ne transmet aucune donnée à ton employeur. La confiance fait partie du défi.</p>
    </section>

    <nav v-if="state && !state.onboarding && !state.challengeOnboarding" class="bottom-nav">
      <button class="nav-item" :class="{ active: activeView === 'home' }" @click="activeView = 'home'"><span>⌂</span>Accueil</button><button class="nav-item" :class="{ active: activeView === 'challenges' }" @click="activeView = 'challenges'"><span>⚡</span>Défis</button>
      <button class="central-action" @click="openCheckin(state.challenge)">✓</button>
      <button class="nav-item" :class="{ active: activeView === 'squad' }" @click="activeView = 'squad'"><span>♟</span>La bande</button><button class="nav-item" :class="{ active: activeView === 'profile' }" @click="activeView = 'profile'"><span>☺</span>Profil</button>
    </nav>
  </main>

  <Transition name="toast"><div v-if="toast" class="toast">{{ toast }}</div></Transition>

  <div v-if="checkinOpen" class="modal-backdrop" @click.self="checkinOpen = false">
    <div class="dialog-card">
      <button type="button" class="dialog-close" @click="checkinOpen = false">×</button><div class="celebration">🔥</div>
      <p class="eyebrow">{{ checkinChallenge?.title }}</p><h2>Objectif : {{ checkinChallenge?.todayTarget || checkinChallenge?.dailyTarget }}</h2><p>Une journée de plus tenue ensemble. L’équipe est fière de toi.</p>
      <label>Un mot pour la bande ? <span>facultatif</span></label><textarea v-model="note" rows="3" placeholder="Facile. Enfin presque."></textarea>
      <div class="quick-reactions"><button v-for="item in [['😎','Facile'],['🥵','Ça pique'],['💀','Adieu']]" :key="item[0]" type="button" class="mood" :class="{ selected: mood === item[0] }" @click="mood = item[0]">{{ item[0] }} {{ item[1] }}</button></div>
      <button type="button" class="confirm-button" :disabled="saving" @click="checkin">{{ saving ? "Envoi…" : "Valider et fanfaronner" }}</button>
    </div>
  </div>

  <div v-if="postOpen" class="modal-backdrop" @click.self="postOpen = false">
    <div class="dialog-card">
      <button type="button" class="dialog-close" @click="postOpen = false">×</button><p class="eyebrow">LE VESTIAIRE</p><h2>Raconte-nous tout</h2>
      <textarea v-model="postText" rows="5" placeholder="Un exploit, une excuse créative…"></textarea><button type="button" class="confirm-button" :disabled="saving" @click="publishPost">{{ saving ? "Publication…" : "Publier" }}</button>
    </div>
  </div>

  <div v-if="challengeOpen" class="modal-backdrop" @click.self="challengeOpen = false">
    <div class="dialog-card challenge-builder">
      <button type="button" class="dialog-close" @click="challengeOpen = false">×</button>
      <p class="eyebrow">NOUVEAU CHALLENGE</p><h2>On remet ça ?</h2>
      <label>Nom du challenge</label><input v-model="challengeTitle" placeholder="5 km par semaine" maxlength="80">
      <label>Description</label><textarea v-model="challengeDescription" rows="2" placeholder="Le défi qui va faire parler la machine à café…"></textarea>
      <label>Évolution de l’objectif</label>
      <div class="progression-toggle"><button :class="{ active: challengeTargetMode === 'fixed' }" @click="challengeTargetMode = 'fixed'">Fixe</button><button :class="{ active: challengeTargetMode === 'linear' }" @click="challengeTargetMode = 'linear'">Progressif</button></div>
      <div class="form-grid"><div><label>{{ challengeTargetMode === "linear" ? "Jour 1" : "Objectif quotidien" }}</label><input v-model.number="challengeTarget" type="number" min="1"></div><div v-if="challengeTargetMode === 'linear'"><label>+ chaque jour</label><input v-model.number="challengeIncrement" type="number" min="0"></div><div><label>Durée</label><select v-model.number="challengeDuration"><option :value="7">7 jours</option><option :value="14">14 jours</option><option :value="30">30 jours</option><option :value="60">60 jours</option></select></div></div>
      <p v-if="challengeTargetMode === 'linear'" class="progression-preview">10, 15, 20… l’objectif évolue automatiquement chaque jour.</p>
      <label>Récompense</label><input v-model="challengeReward" placeholder="Un déjeuner d’équipe">
      <button type="button" class="text-button" @click="challengeOpen = false">Annuler</button>
      <button type="button" class="confirm-button" :disabled="saving" @click="createChallenge">{{ saving ? "Lancement…" : "Lancer ce challenge" }}</button>
    </div>
  </div>

  <div v-if="joinTeamOpen" class="modal-backdrop" @click.self="joinTeamOpen = false">
    <div class="dialog-card onboarding-card">
      <button type="button" class="dialog-close" @click="joinTeamOpen = false">×</button>
      <p class="eyebrow">REJOINDRE UNE ÉQUIPE</p>
      <h2>Change de bande</h2>
      <p>Saisis le code d’invitation de l’autre équipe pour voir son défi.</p>
      <label>Ton prénom</label>
      <input v-model="joinTeamName" placeholder="Camille" maxlength="40">
      <label>Code d’invitation</label>
      <input v-model="joinTeamCode" class="code-input" placeholder="MOLLETS" maxlength="8">
      <p class="reconnect-hint">Déjà membre ? Remets exactement le même pseudo : tu retrouveras ton profil et ton historique.</p>
      <button type="button" class="text-button" @click="joinTeamOpen = false">Annuler</button>
      <button type="button" class="confirm-button" :disabled="saving" @click="confirmJoinTeam">{{ saving ? "Connexion…" : "Rejoindre" }}</button>
    </div>
  </div>

  <div v-if="activeBonus" class="bonus-backdrop">
    <div class="bonus-burst">BAM!</div>
    <div class="bonus-card" :class="activeBonus.mode">
      <span class="bonus-emoji">{{ activeBonus.emoji }}</span>
      <p class="eyebrow">{{ activeBonus.mode === "owned" ? "CARTE BONUS GAGNÉE" : "CARTE REÇUE" }}</p>
      <h2>{{ activeBonus.title }}</h2>
      <p>{{ activeBonus.mode === "received" ? `${activeBonus.senderName} vient de te jouer cette carte. ` : "" }}{{ activeBonus.description }}</p>

      <template v-if="activeBonus.mode === 'owned'">
        <div v-if="bonusTargetOpen" class="bonus-targets">
          <p>À qui réserves-tu ce petit plaisir ?</p>
          <button v-for="member in state.members.filter(item => item.id !== state.currentUserId)" :key="member.id" @click="assignBonus(member.id)">
            <span class="mini-avatar" :class="member.color">{{ member.initials }}</span>{{ member.name }}
          </button>
        </div>
        <div v-else class="bonus-actions">
          <button class="secondary-button" @click="bonusTargetOpen = true">Choisir</button>
          <button class="bonus-primary" :disabled="saving" @click="assignBonus(null)">Au hasard 🎲</button>
        </div>
      </template>
      <button v-else class="bonus-primary full" @click="acknowledgeBonus">Encaisser avec panache</button>
    </div>
  </div>
</template>
