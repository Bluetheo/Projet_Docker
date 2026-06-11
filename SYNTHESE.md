# Synthèse — Projet Conteneurisation B2

## 1. Architecture mise en place

L'infrastructure repose sur **Docker Compose** avec six services :

| Service | Rôle |
|---------|------|
| `web1` / `web2` | Applications Flask (Gunicorn) affichant « Serveur Web 1 » et « Serveur Web 2 », connectées à PostgreSQL |
| `db-primary` | PostgreSQL 16 avec table `messages` et données initiales |
| `nginx-lb` | Reverse proxy répartissant la charge (algorithme `least_conn`) |
| `backup-server` | Serveur SSH dédié stockant le dépôt Restic |
| `backup-client` | Agent de sauvegarde (pg_dump + Restic) planifié par cron |

Les réseaux sont segmentés : `frontend` (LB ↔ web) et `backend` (web ↔ DB ↔ backup).

## 2. Stratégie de sauvegarde

- **Outil** : [Restic](https://restic.net/) (open source)
- **Fréquence** : toutes les 5 minutes via `cron` dans `backup-client`
- **Contenu sauvegardé** : dumps PostgreSQL (`pg_dump` format custom)
- **Rétention** : 7 derniers snapshots (`restic forget --keep-last 7`)
- **Chiffrement** : activé nativement par Restic (`RESTIC_PASSWORD`)
- **Transfert** : SFTP over SSH vers `backup-server` (port 22)
- **Accès** : authentification par clé SSH Ed25519 ; seul `backup-client` possède la clé privée

## 3. Mécanisme de résilience

**Approche retenue : load balancer Nginx**

- Répartition de charge entre `web1` et `web2`
- Détection de panne : `max_fails=2`, `fail_timeout=10s`
- Si un serveur web tombe, le LB route automatiquement vers l'autre
- Endpoint `/health` pour les probes

**Alternative non retenue** : réplication PostgreSQL (streaming replication). Elle pourrait être ajoutée pour éliminer le SPOF de la base de données.

## 4. Résultats des tests de panne et restauration

### Test panne web1 (`./scripts/chaos.sh web1`)

| Métrique | Résultat attendu |
|----------|------------------|
| **RTO** | ~0 s — le service reste disponible via web2 |
| **RPO** | ≤ 5 min — intervalle entre sauvegardes cron |

### Test panne web2 (`./scripts/chaos.sh web2`)

| Métrique | Résultat attendu |
|----------|------------------|
| **RTO** | ~0 s — basculement vers web1 |
| **RPO** | ≤ 5 min |

### Test panne base (`./scripts/chaos.sh db`)

| Métrique | Résultat attendu |
|----------|------------------|
| **RTO** | Dépend du redémarrage PostgreSQL (~10-30 s) |
| **RPO** | ≤ 5 min — données depuis dernier dump |

Les résultats détaillés sont enregistrés dans `results/chaos-results.txt` après exécution des scripts.

### Test de restauration (`./scripts/restore.sh`)

1. Liste les snapshots Restic disponibles
2. Restaure le dernier dump PostgreSQL
3. Recrée la base et redémarre les serveurs web
4. Vérifie l'accès via le load balancer

## 5. Propositions d'amélioration

### Supervision et monitoring

- **Prometheus + Grafana** : métriques conteneurs (CPU, RAM, disque), latence HTTP, état des health checks
- **Alertmanager** : alertes email/Slack si un conteneur est down > 1 min
- **cAdvisor** ou **Docker stats exporter** pour la collecte

### Automatisation

- **CI/CD** (GitHub Actions) : build et test automatique du `docker-compose.yml`
- **Ansible/Terraform** : déploiement reproductible sur un serveur distant
- **Watchtower** ou **Renovate** : mise à jour automatique des images de base

### Résilience avancée

- Réplication PostgreSQL (primary + replica avec basculement automatique via Patroni)
- Déploiement multi-nœuds (Docker Swarm ou Kubernetes)
- Sauvegardes off-site (Restic vers S3/B2 en plus du serveur local)
- Tests de chaos réguliers intégrés au pipeline (ex. `chaos.sh` en cron hebdomadaire)

### Sécurité

- Secrets Docker Swarm ou Vault au lieu de variables `.env` en clair
- TLS sur le load balancer (Let's Encrypt)
- Pare-feu réseau entre segments (politiques Docker network)
- Rotation automatique des clés SSH de sauvegarde
