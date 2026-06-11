#!/bin/bash
set -euo pipefail

# Script de simulation de pannes — mesure RTO et RPO
# Usage: ./scripts/chaos.sh [web1|web2|db|all]

SCENARIO="${1:-web1}"
LB_URL="${LB_URL:-http://localhost:8080}"
RESULTS_FILE="${RESULTS_FILE:-./results/chaos-results.txt}"

mkdir -p "$(dirname "$RESULTS_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$RESULTS_FILE"
}

wait_for_service() {
    local max_wait=120
    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        if curl -sf "${LB_URL}/health" >/dev/null 2>&1; then
            echo "$elapsed"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "-1"
    return 1
}

measure_rpo() {
    log "=== Mesure RPO ==="
    log "Insertion d'un message de test avant la panne..."
    local marker="chaos-marker-$(date +%s)"
    curl -sf -X POST "${LB_URL}/api/messages" \
        -H "Content-Type: application/json" \
        -d "{\"contenu\": \"${marker}\"}" >/dev/null || true
    log "Marqueur inséré : ${marker}"

    local last_backup
    last_backup=$(docker exec backup-client restic snapshots --json 2>/dev/null \
        | grep -o '"time":"[^"]*"' | tail -1 | cut -d'"' -f4 || echo "inconnue")
    log "Dernière sauvegarde connue : ${last_backup}"
    log "RPO estimé = temps écoulé depuis la dernière sauvegarde cron (max 5 min)"
}

stop_component() {
    case "$1" in
        web1) docker stop web1 ;;
        web2) docker stop web2 ;;
        db)   docker stop db-primary ;;
        all)
            docker stop web1 web2 db-primary 2>/dev/null || true
            ;;
        *) echo "Scénario inconnu: $1 (web1|web2|db|all)"; exit 1 ;;
    esac
}

start_component() {
    case "$1" in
        web1) docker start web1 ;;
        web2) docker start web2 ;;
        db)
            docker start db-primary
            sleep 5
            docker start web1 web2 2>/dev/null || true
            ;;
        all)
            docker start db-primary
            sleep 5
            docker start web1 web2
            ;;
    esac
}

log "========================================"
log "TEST DE PANNE — scénario: ${SCENARIO}"
log "========================================"

if ! curl -sf "${LB_URL}/health" >/dev/null; then
    log "ERREUR: Le service n'est pas accessible avant le test (${LB_URL})"
    exit 1
fi

log "Service opérationnel avant panne."
measure_rpo

log "Arrêt du composant: ${SCENARIO}"
FAIL_TIME=$(date +%s)
stop_component "$SCENARIO"
sleep 3

if [ "$SCENARIO" = "web1" ] || [ "$SCENARIO" = "web2" ]; then
    if curl -sf "${LB_URL}/health" >/dev/null; then
        log "Le load balancer route encore vers le serveur sain — service toujours disponible."
        RTO=0
    else
        log "Service indisponible, mesure du RTO..."
        RTO=$(wait_for_service || echo "-1")
    fi
elif [ "$SCENARIO" = "db" ]; then
    log "Base arrêtée — les serveurs web devraient afficher une erreur DB."
    RTO="N/A (panne DB, web partiellement disponible)"
else
    RTO=$(wait_for_service || echo "-1")
fi

log "Redémarrage du composant: ${SCENARIO}"
start_component "$SCENARIO"

if [ "$SCENARIO" != "db" ]; then
    RECOVERY_RTO=$(wait_for_service || echo "-1")
    log "RTO mesuré (retour à la normale): ${RECOVERY_RTO} secondes"
else
    RECOVERY_RTO="N/A"
    sleep 10
    if curl -sf "${LB_URL}/health" >/dev/null; then
        log "Service web de nouveau opérationnel après redémarrage DB."
    fi
fi

log "========================================"
log "RÉSUMÉ"
log "  Scénario    : ${SCENARIO}"
log "  RTO         : ${RECOVERY_RTO} s"
log "  RPO estimé  : ≤ 5 min (intervalle cron sauvegarde)"
log "========================================"
