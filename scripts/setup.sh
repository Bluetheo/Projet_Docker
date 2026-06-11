#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH_DIR="${ROOT_DIR}/backup/ssh"

echo "=== Configuration initiale du projet B2 ==="

if ! docker info >/dev/null 2>&1; then
    echo "ERREUR: Docker n'est pas accessible."
    echo "  - Vérifiez que Docker est démarré : sudo systemctl start docker"
    echo "  - Ou ajoutez votre utilisateur au groupe docker : sudo usermod -aG docker \$USER"
    echo "    puis reconnectez-vous."
    exit 1
fi

if [ ! -f "${ROOT_DIR}/.env" ]; then
    cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
    echo "Fichier .env créé depuis .env.example"
fi

mkdir -p "${SSH_DIR}"

if [ ! -f "${SSH_DIR}/id_ed25519" ]; then
    echo "Génération des clés SSH pour les sauvegardes..."
    ssh-keygen -t ed25519 -f "${SSH_DIR}/id_ed25519" -N "" -C "backup-client@projet-b2"
    cp "${SSH_DIR}/id_ed25519.pub" "${SSH_DIR}/authorized_keys"
    chmod 600 "${SSH_DIR}/id_ed25519"
    chmod 644 "${SSH_DIR}/id_ed25519.pub" "${SSH_DIR}/authorized_keys"
    echo "Clés SSH générées dans backup/ssh/"
else
    echo "Clés SSH déjà présentes, synchronisation authorized_keys..."
    cp "${SSH_DIR}/id_ed25519.pub" "${SSH_DIR}/authorized_keys"
fi

echo ""
echo "Lancement de l'infrastructure..."
cd "${ROOT_DIR}"
docker compose up -d --build

echo ""
echo "Attente du démarrage des services..."
sleep 15

echo ""
echo "=== Vérification ==="
echo -n "Load balancer (port 8080): "
curl -sf http://localhost:8080/health && echo " OK" || echo " EN ATTENTE"

echo -n "Web1 direct: "
docker exec web1 curl -sf http://localhost:5000/health && echo " OK" || echo " ERREUR"

echo -n "Web2 direct: "
docker exec web2 curl -sf http://localhost:5000/health && echo " OK" || echo " ERREUR"

echo -n "Base de données: "
docker exec db-primary pg_isready -U app -d appdb && echo " OK" || echo " ERREUR"

echo ""
echo "Infrastructure prête. Accédez à http://localhost:8080"
