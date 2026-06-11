CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    contenu TEXT NOT NULL,
    serveur VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO messages (contenu, serveur) VALUES
    ('Premier message de démonstration', 'init'),
    ('Données persistantes pour tests RPO', 'init'),
    ('Infrastructure B2 opérationnelle', 'init');
