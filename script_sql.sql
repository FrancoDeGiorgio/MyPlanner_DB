-- I. TABELLA UTENTI (TENANT)
-- Questa tabella memorizzerà i dati di base e l'hash della password. 
-- Per semplicità, stiamo gestendo l'autenticazione con FastAPI , 
-- questa è la tabella che useremo per il login.
CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(), -- L'ID utente/tenant
    name_user TEXT UNIQUE NOT NULL,
    hashed_password TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- II. TABELLA ATTIVITÀ (DATI PROTETTI)
-- Ogni attività è collegata a un utente/tenant tramite la foreign key 'tenant_id'.
CREATE TABLE tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES users(id) NOT NULL, -- La chiave di sicurezza!
    description TEXT NOT NULL,
    date_time TIMESTAMP WITH TIME ZONE NOT NULL,
    completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
