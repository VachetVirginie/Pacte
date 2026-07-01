import { supabase, supabaseConfigured } from "../lib/supabase";

const DEMO_KEY = "pacte-demo-v2";
const IDENTITY_KEY = "pacte-last-identity-v1";
const demoInitial = {
  mode: "demo",
  currentUserId: "vincent",
  inviteCode: "MOLLETS",
  challenge: {
    id: "squats-juillet",
    team: "L'équipe des mollets",
    title: "30 squats par jour",
    description: "Un mois pour transformer nos pauses café en cuisses d'acier.",
    dailyTarget: 30,
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
  ]
};

let realtimeChannel;

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function readDemo() {
  try {
    return JSON.parse(localStorage.getItem(DEMO_KEY)) || clone(demoInitial);
  } catch {
    return clone(demoInitial);
  }
}

function saveDemo(state) {
  localStorage.setItem(DEMO_KEY, JSON.stringify(state));
  return state;
}

function readIdentity() {
  try {
    return JSON.parse(localStorage.getItem(IDENTITY_KEY));
  } catch {
    return null;
  }
}

function saveIdentity(inviteCode, memberName) {
  localStorage.setItem(IDENTITY_KEY, JSON.stringify({
    inviteCode: inviteCode.toUpperCase(),
    memberName
  }));
}

function initials(name) {
  return name.split(/\s+/).slice(0, 2).map(part => part[0]).join("").toUpperCase();
}

async function ensureSession() {
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw new Error(`Supabase session : ${sessionError.message}`);
  if (session) return session;
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw new Error(`Connexion anonyme : ${error.message}`);
  return data.session;
}

async function rpc(name, params = {}) {
  const { data, error } = await supabase.rpc(name, params);
  if (error) throw error;
  return data;
}

export const pacte = {
  isLive: supabaseConfigured,

  async initialize() {
    if (!supabaseConfigured) return readDemo();
    await ensureSession();
    let state = await this.load();
    const identity = readIdentity();
    if (state?.onboarding && identity?.inviteCode && identity?.memberName) {
      try {
        await rpc("join_team", {
          p_invite_code: identity.inviteCode,
          p_member_name: identity.memberName
        });
        state = await this.load();
      } catch {
        // L'identité mémorisée peut appartenir à une équipe supprimée.
      }
    }
    return state;
  },

  async load() {
    if (!supabaseConfigured) return readDemo();
    const data = await rpc("get_app_state");
    if (data?.onboarding) return { onboarding: true, mode: "live" };
    if (data?.challengeOnboarding) return data;

    const [bonusState, wallPosts] = await Promise.all([
      rpc("get_bonus_state"),
      rpc("get_wall_posts")
    ]);

    const challenges = (data.challenges || [data.challenge]).map(challenge => {
      let todayTarget = Number(challenge.todayTarget || challenge.dailyTarget);
      const effects = (bonusState.effects || []).filter(effect => effect.challengeId === challenge.id);
      effects.forEach(effect => {
        if (effect.effectMode === "multiply") todayTarget = Math.max(1, Math.round(todayTarget * Number(effect.effectValue)));
        if (effect.effectMode === "add") todayTarget = Math.max(1, todayTarget + Number(effect.effectValue));
      });
      return { ...challenge, baseTodayTarget: challenge.todayTarget, todayTarget, activeEffects: effects };
    });

    return {
      ...data,
      challenges,
      challenge: challenges[0],
      posts: wallPosts,
      ownedCards: bonusState.ownedCards || [],
      receivedCards: bonusState.receivedCards || []
    };
  },

  async createTeam(teamName, memberName) {
    if (!supabaseConfigured) {
      const data = readDemo();
      data.challengeOnboarding = true;
      data.teamName = teamName;
      const me = data.members.find(member => member.id === data.currentUserId);
      me.name = memberName;
      me.initials = initials(memberName);
      return saveDemo(data);
    }
    await rpc("create_team", { p_team_name: teamName, p_member_name: memberName });
    const state = await this.load();
    saveIdentity(state.inviteCode, memberName);
    return state;
  },

  async createChallenge(challenge) {
    if (!supabaseConfigured) {
      const data = readDemo();
      data.challenge = {
        id: String(Date.now()),
        team: data.teamName || data.challenge.team,
        title: challenge.title,
        description: challenge.description,
        dailyTarget: Number(challenge.dailyTarget),
        reward: challenge.reward || "La gloire éternelle",
        rewardAt: Number(challenge.rewardAt)
      };
      data.challenge.targetMode = challenge.targetMode;
      data.challenge.dailyIncrement = Number(challenge.dailyIncrement || 0);
      data.challenge.todayTarget = Number(challenge.dailyTarget);
      data.challenge.checkedIn = false;
      data.challenge.doneCount = 0;
      data.challenges = [data.challenge, ...(data.challenges || [])];
      data.challengeOnboarding = false;
      data.progress = 0;
      data.members.forEach(member => { member.checkedIn = false; });
      return saveDemo(data);
    }
    await rpc("create_challenge_v2", {
      p_title: challenge.title,
      p_description: challenge.description || "",
      p_target_mode: challenge.targetMode || "fixed",
      p_start_target: Number(challenge.dailyTarget),
      p_daily_increment: Number(challenge.dailyIncrement || 0),
      p_duration_days: Number(challenge.durationDays),
      p_reward: challenge.reward || "La gloire éternelle",
      p_reward_at: Number(challenge.rewardAt)
    });
    return this.load();
  },

  async deleteChallenge(challengeId) {
    if (!supabaseConfigured) {
      const data = readDemo();
      data.challenges = (data.challenges || [data.challenge]).filter(challenge => challenge.id !== challengeId);
      data.challenge = data.challenges[0] || null;
      if (!data.challenge) {
        data.challengeOnboarding = true;
        data.progress = 0;
      } else {
        data.challengeOnboarding = false;
        data.progress = data.challenge.progress || 0;
      }
      return saveDemo(data);
    }
    await rpc("delete_challenge", { p_challenge_id: challengeId });
    return this.load();
  },

  async joinTeam(inviteCode, memberName) {
    if (!supabaseConfigured) return this.createTeam("Ma nouvelle bande", memberName);
    await rpc("join_team", { p_invite_code: inviteCode.toUpperCase(), p_member_name: memberName });
    saveIdentity(inviteCode, memberName);
    return this.load();
  },

  async checkin(challengeId, note, mood) {
    if (!supabaseConfigured) {
      const data = readDemo();
      const member = data.members.find(item => item.id === data.currentUserId);
      if (!member.checkedIn) {
        member.checkedIn = true;
        data.progress = Math.min(100, data.progress + 2);
        if (note.trim()) data.posts.unshift({ id: Date.now(), authorId: member.id, body: note.trim(), time: "à l'instant", reactions: { [mood]: 0 } });
      }
      return saveDemo(data);
    }
    await rpc("check_in_challenge", {
      p_challenge_id: challengeId,
      p_note: note || null,
      p_mood: mood
    });
    return this.load();
  },

  async publishPost(body) {
    if (!supabaseConfigured) {
      const data = readDemo();
      data.posts.unshift({ id: Date.now(), authorId: data.currentUserId, body, time: "à l'instant", reactions: {} });
      return saveDemo(data);
    }
    await rpc("add_post", { p_body: body });
    return this.load();
  },

  async react(postId, emoji) {
    if (!supabaseConfigured) {
      const data = readDemo();
      const post = data.posts.find(item => String(item.id) === String(postId));
      post.reactions[emoji] = (post.reactions[emoji] || 0) + 1;
      return saveDemo(data);
    }
    await rpc("toggle_reaction", { p_post_id: postId, p_emoji: emoji });
    return this.load();
  },

  async assignBonus(bonusId, targetMemberId = null) {
    if (!supabaseConfigured) return readDemo();
    await rpc("assign_bonus_card", {
      p_bonus_id: bonusId,
      p_target_member_id: targetMemberId
    });
    return this.load();
  },

  async acknowledgeBonus(bonusId) {
    if (!supabaseConfigured) return readDemo();
    await rpc("acknowledge_bonus_card", { p_bonus_id: bonusId });
    return this.load();
  },

  async nudge(memberId) {
    if (!supabaseConfigured) return { demo: true };
    await rpc("send_nudge", { p_member_id: memberId });
    return { ok: true };
  },

  async savePushSubscription(subscription) {
    if (!supabaseConfigured) return;
    await rpc("save_push_subscription", { p_subscription: subscription.toJSON() });
  },

  subscribe(onChange) {
    if (!supabaseConfigured) return () => {};
    let timeout;
    realtimeChannel = supabase.channel("pacte-live")
      .on("postgres_changes", { event: "*", schema: "public" }, () => {
        clearTimeout(timeout);
        timeout = setTimeout(onChange, 250);
      })
      .subscribe();
    return () => {
      clearTimeout(timeout);
      if (realtimeChannel) supabase.removeChannel(realtimeChannel);
    };
  }
};
