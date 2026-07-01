# Pacte

Prototype PWA de défis collectifs : Vue 3 côté interface, API Node/Express et stockage JSON côté serveur.

## Lancer en local

```bash
npm install
npm run dev
```

Ouvrez ensuite `http://127.0.0.1:5173`.

## Notifications Web Push

L'application fonctionne sans compte Apple ni Google Play. Pour activer l'envoi de vraies notifications :

```bash
npx web-push generate-vapid-keys
```

Des clés locales sont déjà présentes dans le fichier `.env` ignoré par Git. Pour une mise en production, générez de nouvelles clés, remplacez celles du fichier et gardez la clé privée uniquement sur le serveur. Le site doit être servi en HTTPS. Sur iPhone/iPad, l'utilisateur doit installer la PWA sur l'écran d'accueil avant d'autoriser les notifications.

Sans clés VAPID, l'interface et la demande d'autorisation restent testables ; les relances distantes tournent en mode démonstration.

## Données

Les check-ins, messages, réactions et abonnements Push sont enregistrés dans `server/data.json`, créé au premier lancement. Pour un déploiement réel, remplacer ce stockage par PostgreSQL et ajouter l'authentification des équipes.
# Pacte
