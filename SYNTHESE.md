# Synthèse — Projet Conteneurisation B2

**Auteur :** Théo Darribau  
**Date :** 11 juin 2026  
**Projet :** Infrastructure conteneurisée avec sauvegarde, sécurisation et résilience

---

## Introduction

Ce projet consiste à déployer une infrastructure complète sous Docker Compose répondant aux six étapes du sujet B2 : deux serveurs web, une base de données PostgreSQL, un serveur de sauvegarde dédié, une stratégie de sécurisation des sauvegardes, un mécanisme de résilience face aux pannes, et des tests de continuité de service (RTO/RPO) ainsi qu'une restauration complète.

L'objectif est de garantir la disponibilité du service web même en cas de panne d'un composant, tout en protégeant les données critiques par des sauvegardes chiffrées et automatisées.

---

## 1. Architecture mise en place

### Schéma général

```
                         ┌─────────────┐
                         │  nginx-lb   │  :8080
                         └──────┬──────┘
                    ┌────────────┼────────────┐
                    ▼                         ▼
              ┌──────────┐              ┌──────────┐
              │   web1   │              │   web2   │
              │ Flask +  │              │ Flask +  │
              │ Gunicorn │              │ Gunicorn │
              └────┬─────┘              └────┬─────┘
                   └────────────┬────────────┘
                                ▼
                         ┌─────────────┐
                         │  db-primary │  PostgreSQL 16
                         └──────┬──────┘
                                │
              ┌─────────────────┴─────────────────┐
              ▼                                   ▼
      ┌──────────────┐                    ┌──────────────┐
      │ backup-client│                    │ backup-server│
      │  (agent)     │── volume partagé ─▶│  SSH + Restic│
      └──────────────┘                    └──────────────┘
```

### Services déployés

| Service | Technologie | Rôle |
|---------|-------------|------|
| `web1` | Python Flask + Gunicorn | Affiche « Serveur Web 1 », lit/écrit en base |
| `web2` | Python Flask + Gunicorn | Affiche « Serveur Web 2 », lit/écrit en base |
| `db-primary` | PostgreSQL 16 | Stocke la table `messages` et les données applicatives |
| `nginx-lb` | Nginx 1.27 | Reverse proxy, répartition de charge entre web1 et web2 |
| `backup-server` | Alpine + OpenSSH + Restic | Machine dédiée aux sauvegardes |
| `backup-client` | Alpine + Restic + pg_dump | Agent de sauvegarde automatique |

### Réseaux Docker

- **`frontend`** : load balancer ↔ serveurs web (isolation de la couche présentation)
- **`backend`** : serveurs web ↔ base de données ↔ sauvegardes (données et backups)

### Interaction web ↔ base de données

Chaque serveur web expose :
- une page HTML listant les messages en base (`SELECT` sur la table `messages`) ;
- un endpoint `/health` pour les sondes de santé ;
- un endpoint `POST /api/messages` pour insérer de nouvelles données.

La table `messages` est initialisée au démarrage via `db/init.sql` avec trois enregistrements de démonstration.

---

## 2. Stratégie de sauvegarde

### Outil choisi : Restic

[Restic](https://restic.net/) est un outil de sauvegarde open source qui propose nativement :
- la déduplication ;
- le chiffrement AES-256 ;
- la gestion de snapshots ;
- la politique de rétention.

### Contenu sauvegardé

| Élément | Méthode |
|---------|---------|
| Base PostgreSQL | `pg_dump` (format custom) |
| Fichiers de dump | Dossier `/backups/staging` |

### Fréquence et automatisation

- Sauvegarde initiale au démarrage du conteneur `backup-client`
- Puis **toutes les 5 minutes** via une boucle planifiée dans le conteneur
- Rétention : **7 derniers snapshots** (`restic forget --keep-last 7 --prune`)

### Résultats observés

Lors des tests, deux snapshots ont été créés avec succès :

```
ID        Time                 Host       Tags        Paths
------------------------------------------------------------------------
afd98877  2026-06-11 12:08:52  projet-b2  auto,db     /backups/staging
f0c70d20  2026-06-11 12:09:16  projet-b2  auto,db     /backups/staging
```

---

## 3. Sécurisation des sauvegardes

### Chiffrement

Toutes les sauvegardes Restic sont chiffrées via la variable `RESTIC_PASSWORD`. Sans ce mot de passe, les snapshots sont illisibles.

### Transfert sécurisé

Le script de sauvegarde tente en priorité un **transfert SCP via SSH** vers `backup-server` :

```bash
scp dump backup@backup-server:/backups/staging/
```

En cas d'indisponibilité SSH, un **volume Docker partagé** (`backup-data`) assure le transfert des fichiers vers le serveur de sauvegarde. Ce mécanisme de repli garantit la continuité des sauvegardes.

Le serveur `backup-server` expose SSH (port 22) uniquement sur le réseau interne `backend`, non publié vers l'hôte.

### Contrôle d'accès

- Authentification SSH par clé Ed25519 (générée automatiquement au démarrage)
- Utilisateur dédié `backup` sur le serveur de sauvegarde
- `PasswordAuthentication no` — pas de connexion par mot de passe
- `PermitRootLogin no` — root interdit
- `AllowUsers backup` — seul l'utilisateur backup est autorisé
- Le dépôt Restic n'est accessible que depuis le réseau Docker interne

---

## 4. Mécanisme de résilience

### Approche retenue : load balancer Nginx

Parmi les deux options du sujet (load balancer ou réplication PostgreSQL), j'ai choisi le **reverse proxy Nginx** pour éliminer le point de défaillance unique au niveau web.

**Configuration :**
- Algorithme `least_conn` (envoie les requêtes vers le serveur le moins chargé)
- `max_fails=2` et `fail_timeout=10s` (détection de panne automatique)
- Endpoint `/health` pour les sondes de disponibilité

**Comportement en cas de panne :**
Si `web1` tombe, Nginx route automatiquement tout le trafic vers `web2` (et inversement). Le service reste accessible sur `http://localhost:8080` sans intervention manuelle.

### Alternative non retenue

La **réplication PostgreSQL** (streaming replication) aurait éliminé le point de défaillance unique de la base de données. Elle pourrait être ajoutée en amélioration future (voir section 5).

---

## 5. Résultats des tests de panne et restauration

### Test 1 — Panne du serveur web 1

**Commande :** `./scripts/chaos.sh web1`

| Métrique | Résultat obtenu |
|----------|-----------------|
| **RTO** | **0 seconde** — le service est resté disponible via web2 |
| **RPO** | **≤ 5 minutes** — intervalle entre deux sauvegardes cron |

**Observation :** Le load balancer a détecté l'indisponibilité de web1 et a basculé immédiatement vers web2. Aucune interruption de service constatée côté utilisateur. Un marqueur `chaos-marker-*` a été inséré en base avant la panne pour mesurer la perte de données potentielle.

### Test 2 — Panne du serveur web 2

**Commande :** `./scripts/chaos.sh web2`

| Métrique | Résultat obtenu |
|----------|-----------------|
| **RTO** | **0 seconde** — basculement vers web1 |
| **RPO** | **≤ 5 minutes** |

**Observation :** Même comportement que pour web1. La redondance des serveurs web combinée au load balancer assure une haute disponibilité de la couche présentation.

### Test 3 — Panne de la base de données

**Commande :** `./scripts/chaos.sh db`

| Métrique | Résultat obtenu |
|----------|-----------------|
| **RTO** | **~10 à 30 secondes** — temps de redémarrage PostgreSQL |
| **RPO** | **≤ 5 minutes** — données restaurables depuis le dernier dump |

**Observation :** Pendant la panne, les serveurs web restent accessibles mais affichent une erreur de connexion à la base. Après redémarrage de `db-primary`, le service retrouve son fonctionnement normal.

### Test 4 — Restauration complète

**Commande :** `./scripts/restore.sh`

Procédure :
1. Liste des snapshots Restic disponibles
2. Restauration du dernier dump PostgreSQL depuis le dépôt chiffré
3. Recréation de la base `appdb`
4. Redémarrage des serveurs web
5. Vérification de l'accès via le load balancer

**Résultat :** Restauration réussie. Les données de la table `messages` sont retrouvées après l'opération.

### Synthèse des métriques

| Scénario | RTO mesuré | RPO estimé | Service maintenu ? |
|----------|------------|------------|-------------------|
| Panne web1 | 0 s | ≤ 5 min | Oui |
| Panne web2 | 0 s | ≤ 5 min | Oui |
| Panne DB | ~10-30 s | ≤ 5 min | Partiellement (web sans DB) |
| Restauration | ~30 s | 0 (données du snapshot) | Oui après restauration |

---

## 6. Captures d'écran (annexes)

| Figure | Description |
|--------|-------------|
| Figure 1 | Interface web — « Serveur Web 1 », base de données connectée, messages affichés |
| Figure 2 | `docker compose ps` — les 6 conteneurs opérationnels |
| Figure 3 | `restic snapshots` — deux snapshots chiffrés présents |
| Figure 4 | `./scripts/chaos.sh web1` — RTO = 0 s, service toujours disponible |

---

## 7. Propositions d'amélioration

### Supervision et monitoring

- **Prometheus + Grafana** : collecte des métriques (CPU, RAM, latence HTTP, état des health checks)
- **Alertmanager** : alertes automatiques si un conteneur est arrêté plus d'une minute
- **Uptime Kuma** ou **Healthchecks.io** : surveillance externe de `http://localhost:8080/health`

### Automatisation

- **GitHub Actions** : pipeline CI/CD pour builder et tester le `docker-compose.yml` à chaque commit
- **Ansible** : déploiement reproductible sur un serveur distant
- **Renovate** : mise à jour automatique des images Docker de base

### Résilience avancée

- **Réplication PostgreSQL** (primary + replica) avec basculement automatique via Patroni ou repmgr
- **Déploiement multi-nœuds** avec Docker Swarm ou Kubernetes
- **Sauvegardes off-site** : envoi des snapshots Restic vers un stockage distant (S3, Backblaze B2)
- **Tests de chaos réguliers** : exécution hebdomadaire de `chaos.sh` en cron

### Sécurité

- **Docker Secrets** ou **HashiCorp Vault** pour stocker les mots de passe (remplacer le fichier `.env`)
- **TLS/HTTPS** sur le load balancer avec Let's Encrypt
- **Politiques réseau Docker** pour restreindre les flux entre conteneurs
- **Rotation automatique** des clés SSH de sauvegarde

---

## Conclusion

L'infrastructure déployée répond aux six étapes du projet B2 :

1. **Deux serveurs web** opérationnels, connectés à PostgreSQL
2. **Serveur de sauvegarde** dédié avec Restic et planification automatique
3. **Sauvegardes chiffrées** avec transfert sécurisé (SCP/SSH + volume partagé)
4. **Résilience** assurée par un load balancer Nginx (RTO = 0 s en cas de panne web)
5. **Tests de panne** documentés avec mesures RTO et RPO
6. **Restauration complète** validée depuis le dépôt Restic

Le point de défaillance unique restant est la base de données PostgreSQL. Sa réplication constituerait la prochaine étape naturelle pour atteindre une haute disponibilité complète.

---

*Théo Darribau — Projet Conteneurisation B2 — Juin 2026*
