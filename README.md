# Projet Conteneurisation B2

Infrastructure Docker complète : deux serveurs web, PostgreSQL, load balancer, sauvegardes Restic chiffrées et scripts de test de résilience.

## Architecture

```
                    ┌─────────────┐
                    │  nginx-lb   │ :8080
                    └──────┬──────┘
              ┌────────────┼────────────┐
              ▼                         ▼
        ┌──────────┐              ┌──────────┐
        │   web1   │              │   web2   │
        └────┬─────┘              └────┬─────┘
             └────────────┬────────────┘
                          ▼
                   ┌─────────────┐
                   │  db-primary │
                   └──────┬──────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
      ┌──────────────┐        ┌──────────────┐
      │ backup-client│─SSH──▶│ backup-server│
      │   (cron)     │       │   (Restic)   │
      └──────────────┘        └──────────────┘
```

## Démarrage rapide

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

Puis ouvrir [http://localhost:8080](http://localhost:8080).

## Commandes utiles

| Commande | Description |
|----------|-------------|
| `docker compose ps` | État des conteneurs |
| `docker compose logs -f` | Logs en temps réel |
| `./scripts/chaos.sh web1` | Simule la panne du serveur web 1 |
| `./scripts/chaos.sh web2` | Simule la panne du serveur web 2 |
| `./scripts/chaos.sh db` | Simule la panne de la base |
| `./scripts/restore.sh` | Restauration complète depuis Restic |

## Étapes du projet

1. **Infrastructure** — web1, web2, PostgreSQL avec interaction
2. **Sauvegarde** — Restic + cron (toutes les 5 min)
3. **Sécurité** — chiffrement Restic + transfert SFTP/SSH + clés autorisées
4. **Résilience** — load balancer Nginx (least_conn, health checks)
5. **Tests de panne** — `scripts/chaos.sh` mesure RTO/RPO
6. **Synthèse** — voir `SYNTHESE.md`

## Arrêt

```bash
docker compose down
docker compose down -v   # supprime aussi les volumes
```
