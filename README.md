# My Planner – Database

Schema PostgreSQL per **My Planner**, sistema multi-tenant di gestione attività con Row-Level Security (RLS). Questo repository contiene gli script SQL per creare tabelle, configurare policy RLS e gestire migrazioni dello schema.

---

## 📂 Struttura Repository

MyPlanner_DB/
├── script_sql.sql # Creazione tabelle users/tasks + migrazione schema
├── policy RLS.sql # RLS policies e funzione get_current_tenant_id()
└── README.md # Documentazione (questo file)


---

## 🗄️ Schema Database

### Tabella `users` (Tenant)

Memorizza gli utenti/tenant del sistema con password hashate (gestite da FastAPI).

```sql
CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name_user TEXT UNIQUE NOT NULL,
    hashed_password TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Note:**
- `id` è usato come `tenant_id` nelle altre tabelle per isolamento multi-tenant
- `name_user` è usato nel claim JWT `sub` per RLS
- Password hashate lato backend (Bcrypt), mai salvate in chiaro

---

### Tabella `tasks` (Schema Finale)

Memorizza le attività associate a ciascun tenant.

```sql
CREATE TABLE tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES users(id),
    title VARCHAR(150) NOT NULL,
    description TEXT NOT NULL,
    color VARCHAR(20) NOT NULL DEFAULT 'green',
    date_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NULL,
    duration_minutes INTEGER NULL CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 5 AND 1440),
    completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Vincoli e Regole:**
- `tenant_id`: FK obbligatoria verso `users(id)` per isolamento
- `title`: max 150 caratteri
- `description`: testo libero
- `color`: valori consigliati `green|purple|orange|cyan|pink|yellow`
- `end_time` e `duration_minutes`: **mutuamente esclusivi** (enforced lato backend Pydantic, non DB)
- `duration_minutes`: se valorizzato, range 5-1440 minuti (5 min - 24h)

---

### 🔄 Processo di Creazione (script_sql.sql)

⚠️ **Importante**: `script_sql.sql` crea le tabelle in DUE fasi per retrocompatibilità:

**Fase 1 - Schema Base** (legacy):
```sql
CREATE TABLE tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES users(id),
    description TEXT NOT NULL,
    date_time TIMESTAMPTZ NOT NULL,
    completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Fase 2 - Migrazione Avanzata**:
```sql
ALTER TABLE tasks
    ADD COLUMN title VARCHAR(150) NOT NULL DEFAULT 'Nuova task',
    ADD COLUMN color VARCHAR(20) NOT NULL DEFAULT 'green',
    ADD COLUMN end_time TIMESTAMPTZ NULL,
    ADD COLUMN duration_minutes INTEGER NULL CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 5 AND 1440);
```

**Perché in due fasi?**
- Permette di eseguire lo script anche su database esistenti con schema legacy
- I default temporanei (`'Nuova task'`, `'green'`) evitano errori su righe esistenti
- Dopo la migrazione, i default possono essere rimossi manualmente se necessario

---

## 🔐 Row-Level Security (RLS)

Le policy RLS garantiscono che ogni tenant acceda **solo ai propri dati**.

### Funzione Helper: `get_current_tenant_id()`

Estrae l'ID tenant dal claim JWT `sub` (username) impostato da FastAPI:

```sql
CREATE OR REPLACE FUNCTION get_current_tenant_id()
RETURNS uuid AS $$
  SELECT id 
  FROM users 
  WHERE name_user = current_setting('request.jwt.claim.sub', TRUE)
$$ LANGUAGE sql STABLE;
```

**Funzionamento:**
1. FastAPI esegue `SET LOCAL request.jwt.claim.sub = '<username>'` prima di ogni query
2. La funzione legge questo setting e restituisce l'UUID corrispondente
3. Le policy RLS usano questo UUID per filtrare i dati

---

### Policy RLS su Tabella `tasks`

```sql
-- Abilita RLS (CRITICO!)
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Policy SELECT: leggi solo le tue task
CREATE POLICY "Tenants can only read their own tasks"
  ON tasks FOR SELECT TO authenticated
  USING (tenant_id = get_current_tenant_id());

-- Policy INSERT: crea task solo per te stesso
CREATE POLICY "Tenants can insert their own tasks"
  ON tasks FOR INSERT TO authenticated
  WITH CHECK (tenant_id = get_current_tenant_id());

-- Policy UPDATE: modifica solo le tue task
CREATE POLICY "Tenants can update their own tasks"
  ON tasks FOR UPDATE TO authenticated
  USING (tenant_id = get_current_tenant_id())
  WITH CHECK (tenant_id = get_current_tenant_id());

-- Policy DELETE: elimina solo le tue task
CREATE POLICY "Tenants can delete their own tasks"
  ON tasks FOR DELETE TO authenticated
  USING (tenant_id = get_current_tenant_id());
```

**Note:**
- `authenticated` è un ruolo PostgreSQL/Supabase
- In Supabase è predefinito; in PostgreSQL vanilla va creato manualmente
- Il backend deve connettersi con questo ruolo o fare `SET ROLE authenticated`

---

## ⚙️ Setup e Installazione

### Opzione 1: Supabase (Consigliato)

1. **Accedi alla Dashboard SQL** di Supabase:
   - Project > SQL Editor > New query

2. **Esegui gli script in ordine**:
   
   **Passo 1** - Copia e incolla il contenuto di `script_sql.sql`:
   ```sql
   -- Copia TUTTO il contenuto di script_sql.sql qui
   ```
   Click su **RUN** ▶️
   
   **Passo 2** - Copia e incolla il contenuto di `policy RLS.sql`:
   ```sql
   -- Copia TUTTO il contenuto di policy RLS.sql qui
   ```
   Click su **RUN** ▶️

3. **Verifica** nella sezione Table Editor:
   - Tabelle `users` e `tasks` devono essere visibili
   - `tasks` deve avere RLS abilitato (icona lucchetto)

---

### Opzione 2: PostgreSQL Locale / Gestito

1. **Connettiti al database**:
   ```bash
   psql -h localhost -U postgres -d myplanner
   ```

2. **Esegui gli script**:
   ```sql
   \i script_sql.sql
   \i 'policy RLS.sql'
   ```

3. **Crea ruolo `authenticated`** (se non esiste):
   ```sql
   CREATE ROLE authenticated;
   GRANT USAGE ON SCHEMA public TO authenticated;
   GRANT SELECT, INSERT, UPDATE, DELETE ON tasks TO authenticated;
   GRANT SELECT ON users TO authenticated;
   ```

4. **Configura il backend** per usare questo ruolo:
   - Nella connection string, specifica l'utente
   - Oppure esegui `SET ROLE authenticated` dopo la connessione

5. **Verifica creazione**:
   ```sql
   \dt                    -- Lista tabelle
   \d tasks               -- Dettagli tabella tasks
   SELECT * FROM users;   -- Test query
   ```

---

## 🧪 Testing Row-Level Security

### Test Base: Simulare Contesto FastAPI

```sql
-- 1. Crea un utente di test
INSERT INTO users (name_user, hashed_password)
VALUES ('utente_demo', '$2b$12$dummy_hash_for_testing');

-- 2. Assumi ruolo authenticated
SET ROLE authenticated;

-- 3. Imposta il claim JWT (simula FastAPI)
SET LOCAL request.jwt.claim.sub = 'utente_demo';

-- 4. Query protetta: vedrai solo task di utente_demo
SELECT * FROM tasks;
```

---

### Test INSERT: Verifica Isolamento

```sql
-- (continua dalla sessione sopra)

-- Inserisci una task per l'utente corrente
INSERT INTO tasks (tenant_id, title, description, color, date_time, completed)
VALUES (
  get_current_tenant_id(),
  'Task di Test',
  'Verifica RLS funzionante',
  'green',
  NOW(),
  FALSE
);

-- Dovrebbe andare a buon fine e restituire 1 riga
```

---

### Test Blocco Accesso Cross-Tenant

```sql
-- 1. Crea secondo utente
INSERT INTO users (name_user, hashed_password)
VALUES ('altro_utente', '$2b$12$dummy_hash_2');

-- 2. Cambia contesto al secondo utente
SET LOCAL request.jwt.claim.sub = 'altro_utente';

-- 3. Prova a leggere: NON vedrai le task di utente_demo!
SELECT * FROM tasks;
-- Risultato: 0 righe (anche se esistono task nel DB)

-- 4. Prova a modificare una task altrui (prendi l'ID dal test precedente)
UPDATE tasks SET title = 'HACK!' WHERE id = '<uuid_task_utente_demo>';
-- Risultato: 0 righe modificate (RLS blocca l'accesso)
```

---

### Reset Contesto

Dopo i test, resetta il contesto:

```sql
RESET ROLE;                           -- Torna al ruolo originale
RESET request.jwt.claim.sub;         -- Rimuove il claim JWT
```

---

## 🔍 Query Utili per Diagnostica

### Verifica RLS Abilitato

```sql
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'tasks';
-- rowsecurity deve essere 't' (true)
```

---

### Lista Policy Attive

```sql
SELECT schemaname, tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE tablename = 'tasks';
```

---

### Test Funzione `get_current_tenant_id()`

```sql
SET LOCAL request.jwt.claim.sub = 'utente_demo';
SELECT get_current_tenant_id();
-- Deve restituire l'UUID di utente_demo
```

---

### Verifica Integrità Dati

```sql
-- Task orfane (tenant_id non valido)
SELECT t.* 
FROM tasks t
LEFT JOIN users u ON t.tenant_id = u.id
WHERE u.id IS NULL;

-- Conta task per tenant
SELECT u.name_user, COUNT(t.id) as num_tasks
FROM users u
LEFT JOIN tasks t ON u.id = t.tenant_id
GROUP BY u.name_user;
```

---

## 🚨 Troubleshooting

### Errore: "function get_current_tenant_id() does not exist"
- **Causa**: Script `policy RLS.sql` non eseguito
- **Soluzione**: Esegui `policy RLS.sql` completo

---

### Errore: "permission denied for table tasks"
- **Causa**: Ruolo `authenticated` non ha i permessi necessari
- **Soluzione**: 
  ```sql
  GRANT SELECT, INSERT, UPDATE, DELETE ON tasks TO authenticated;
  GRANT SELECT ON users TO authenticated;
  ```

---

### RLS non filtra i dati (vedi tutte le task)
- **Causa 1**: RLS non abilitato
  ```sql
  ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
  ```
- **Causa 2**: Stai usando un ruolo SUPERUSER (bypassa RLS)
  ```sql
  SELECT current_user;  -- Verifica ruolo corrente
  SET ROLE authenticated;  -- Usa ruolo non-super
  ```
- **Causa 3**: Claim JWT non impostato
  ```sql
  SET LOCAL request.jwt.claim.sub = 'username_valido';
  ```

---

### Backend non applica RLS correttamente
- Verifica che FastAPI esegua `execute_protected_query()` per ogni operazione
- Controlla che `SET LOCAL request.jwt.claim.sub` sia eseguito nella stessa transazione della query
- Verifica log backend per errori SQL

---

## 📊 Ottimizzazioni Consigliate

### Indici per Performance

```sql
-- Indice composito per query ordinate per data
CREATE INDEX idx_tasks_tenant_date 
ON tasks (tenant_id, date_time DESC);

-- Indice per lookup rapido per ID
CREATE INDEX idx_tasks_tenant_id 
ON tasks (tenant_id);

-- Indice per filtri su stato completamento
CREATE INDEX idx_tasks_completed 
ON tasks (tenant_id, completed);
```

---

### Constraint Aggiuntivo: End Time vs Duration (Opzionale)

Per enforced l'esclusività a livello DB (oltre a Pydantic):

```sql
ALTER TABLE tasks
ADD CONSTRAINT check_end_time_or_duration
CHECK (
  (end_time IS NULL AND duration_minutes IS NOT NULL) OR
  (end_time IS NOT NULL AND duration_minutes IS NULL) OR
  (end_time IS NULL AND duration_minutes IS NULL)
);
```

**Pro:** Validazione DB-level, più sicuro
**Contro:** Richiede migrazione per dati esistenti

---

## 🔄 Versionamento e Migrazioni Future

### Convenzioni
- Ogni modifica schema → nuovo file `migrations/YYYY-MM-DD-description.sql`
- Mantenere `script_sql.sql` aggiornato con schema "corrente"
- Mai `DROP TABLE` in produzione → usare `ALTER TABLE` incrementale

### Esempio Migrazione Future

```sql
-- migrations/2025-02-15-add-task-priority.sql
ALTER TABLE tasks ADD COLUMN priority INTEGER DEFAULT 0 CHECK (priority BETWEEN 0 AND 5);
CREATE INDEX idx_tasks_priority ON tasks (tenant_id, priority DESC);
```

---

## 🌐 Integrazione con Backend FastAPI

Il backend si connette al database e:

1. **Connessione**: Usa `psycopg2` con ruolo `authenticated` o esegue `SET ROLE authenticated`
2. **Autenticazione**: Verifica JWT e estrae `username` dal claim `sub`
3. **Query Protette**: Ogni query passa da `execute_protected_query()`:
   ```python
   def execute_protected_query(conn, username, sql_query, params):
       cur.execute("SET ROLE authenticated;")
       cur.execute("SELECT set_config('request.jwt.claim.sub', %s, true)", (username,))
       cur.execute(sql_query, params)  # Query RLS-protected
   ```
4. **Isolamento**: RLS filtra automaticamente i dati per `tenant_id`

**Pattern Multi-Tenant Generale:**
- Ogni nuova tabella multi-tenant deve avere `tenant_id` FK a `users(id)`
- Replicare le 4 policy RLS (SELECT, INSERT, UPDATE, DELETE)
- Usare sempre `get_current_tenant_id()` nelle policy

---

## 📋 Roadmap Database

- [ ] Tabella `task_events` per audit log (chi ha modificato cosa e quando)
- [ ] Trigger per auto-popolamento `task_events` su INSERT/UPDATE/DELETE
- [ ] Indici ottimizzati su `tasks (tenant_id, date_time DESC)`
- [ ] Constraint DB per esclusività `end_time` / `duration_minutes`
- [ ] Script seed per dati demo (ambiente staging/testing)
- [ ] Backup automatici e retention policy
- [ ] Soft delete (`deleted_at TIMESTAMPTZ`) invece di DELETE hard

---

## 📄 Licenza

Parte della suite **My Planner** – schema e policy rilasciati sotto licenza MIT.

---

## 🤝 Contribuire

Per proporre modifiche allo schema:

1. Crea branch `db/feature-name`
2. Aggiungi migration script in `migrations/`
3. Aggiorna `script_sql.sql` con schema finale
4. Documenta cambiamenti in questo README
5. Testa RLS su dati demo
6. Apri Pull Request

Per segnalazioni bug o domande, apri una issue su GitHub.