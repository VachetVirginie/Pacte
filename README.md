# Pacte

PWA Vue 3 de défis entre collègues, avec Supabase pour l’authentification anonyme, PostgreSQL, les règles de sécurité, le temps réel et les notifications Web Push.

L’application démarre immédiatement en **mode démonstration** si Supabase n’est pas encore configuré. Les données de démonstration restent dans le navigateur.

## 1. Lancer l’application

Prérequis : Node.js 20 ou plus récent.

```bash
npm install
npm run dev
```

Ouvrir [http://localhost:5173](http://localhost:5173).

## 2. Créer le backend Supabase

1. Créer un projet sur [Supabase](https://database.new).
2. Dans **Authentication → Providers → Anonymous**, activer les connexions anonymes.
3. À la racine du projet :

```bash
npx supabase login
npx supabase link --project-ref VOTRE_PROJECT_REF
npx supabase db push
```

La migration crée les équipes, membres, défis, check-ins, publications, réactions et abonnements Push. Elle active également les règles RLS et le temps réel.

## 3. Relier Vue à Supabase

Copier `.env.example` vers `.env.local`, puis renseigner :

```dotenv
VITE_SUPABASE_URL=https://VOTRE-PROJET.supabase.co
VITE_SUPABASE_ANON_KEY=VOTRE_CLE_PUBLISHABLE_OU_ANON
VITE_VAPID_PUBLIC_KEY=VOTRE_CLE_VAPID_PUBLIQUE
```

Ces deux premières valeurs se trouvent dans **Project Settings → API**. Ne jamais mettre la `service_role` dans le frontend.

## 4. Activer les notifications Web Push

Aucun compte Apple Developer ni Google Play n’est nécessaire.

Générer les clés :

```bash
npx web-push generate-vapid-keys
```

Créer `supabase/.env.local` à partir de l’exemple, puis déployer la fonction :

```bash
npx supabase secrets set --env-file supabase/.env.local
npx supabase functions deploy send-web-push --no-verify-jwt
```

Dans **Database → Webhooks**, créer un webhook :

- table : `notifications`
- événement : `INSERT`
- cible : Edge Function `send-web-push`
- header : `x-webhook-secret`, avec la même valeur que `WEBHOOK_SECRET`

Sur iPhone/iPad, l’utilisateur doit ajouter la PWA à l’écran d’accueil avant d’autoriser les notifications. En production, le site doit être en HTTPS.

## 5. Déployer le frontend

Le projet contient déjà `netlify.toml` et `vercel.json`.

Sur Netlify ou Vercel :

1. Importer le dépôt.
2. Ajouter les trois variables `VITE_*`.
3. Lancer le déploiement ; la commande est `npm run build` et le dossier publié est `dist`.

Test local de la version de production :

```bash
npm run build
npm run preview
```

## Architecture

- `src/services/pacte.js` : accès Supabase et mode démonstration.
- `supabase/migrations/` : schéma PostgreSQL, fonctions métier et RLS.
- `supabase/functions/send-web-push/` : envoi des notifications.
- `public/sw.js` : réception des notifications et installation PWA.
