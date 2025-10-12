
---

## 🗄️ Schema Iniziale

### Tabella `users`

```sql
CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name_user TEXT UNIQUE NOT NULL,
    hashed_password TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Tabella `tasks`

```sql
CREATE TABLE tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES users(id),
    title VARCHAR(150) NOT NULL,
    description TEXT NOT NULL,
    color VARCHAR(20) NOT NULL DEFAULT 'green',
    date_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NULL,
    duration_minutes INTEGER NULL CHECK (duration_minutes BETWEEN 5 AND 1440),
    completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

- `end_time` e `duration_minutes` si escludono a vicenda (enforce lato backend/Pydantic).
- `color` default `green` per mantenere retrocompatibilità con dati pre-esistenti.

---

## 🔐 Row-Level Security

Script `policy RLS.sql`:

```sql
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION get_current_tenant_id()
RETURNS uuid AS $$
  SELECT id
  FROM users
  WHERE name_user = current_setting('request.jwt.claim.sub', TRUE)
$$ LANGUAGE sql STABLE;

CREATE POLICY "Tenants can only read their own tasks"
  ON tasks FOR SELECT TO authenticated
  USING (tenant_id = get_current_tenant_id());

CREATE POLICY "Tenants can insert their own tasks"
  ON tasks FOR INSERT TO authenticated
  WITH CHECK (tenant_id = get_current_tenant_id());

CREATE POLICY "Tenants can update their own tasks"
  ON tasks FOR UPDATE TO authenticated
  USING (tenant_id = get_current_tenant_id())
  WITH CHECK (tenant_id = get_current_tenant_id());

CREATE POLICY "Tenants can delete their own tasks"
  ON tasks FOR DELETE TO authenticated
  USING (tenant_id = get_current_tenant_id());
```

- `authenticated` è un ruolo database che viene GRANTato al connection pool usato dal backend.
- FastAPI setta `request.jwt.claim.sub` (tramite `SET LOCAL`) prima di ogni query con `execute_protected_query`.

---

## ⚙️ Applicazione Script

### Supabase / PostgreSQL

1. Connettersi tramite dashboard SQL o `psql`.
2. Eseguire nell’ordine:
   ```sql
   \i script_sql.sql;
   \i "policy RLS.sql";
   ```
3. Verificare:
   ```sql
   \dt
   \d tasks
   ```

### Migrazioni Post-Aggiornamento Task

Per passare da schema legacy (solo description/date_time/completed) a schema avanzato:

```sql
ALTER TABLE tasks
    ADD COLUMN title VARCHAR(150) NOT NULL DEFAULT 'Nuova task',
    ADD COLUMN color VARCHAR(20) NOT NULL DEFAULT 'green',
    ADD COLUMN end_time TIMESTAMPTZ NULL,
    ADD COLUMN duration_minutes INTEGER NULL CHECK (duration_minutes BETWEEN 5 AND 1440);

-- Popola le colonne con valori coerenti (opzionale)
UPDATE tasks
SET
    title = description,
    color = 'green',
    end_time = date_time + INTERVAL '1 hour';

ALTER TABLE tasks
    ALTER COLUMN title DROP DEFAULT;
```

---

## 🧪 Testing RLS

Simula la sessione FastAPI da `psql`:

```sql
SET ROLE authenticated;                                  -- assume ruolo API
SET LOCAL request.jwt.claim.sub = 'utente_demo';          -- claim JWT
SELECT * FROM tasks;                                      -- solo record con tenant_id appropriato
```

Per verificare permessi di modifica:

```sql
INSERT INTO tasks (tenant_id, title, description, color, date_time, completed)
VALUES (
  get_current_tenant_id(),
  'Prova RLS',
  'Task demo',
  'green',
  NOW(),
  FALSE
);
```

---

## 🔄 Versionamento e Convenzioni

- Ogni modifica allo schema deve essere tracciata con un nuovo script (es. `2025-01-add-reminders.sql`) mantenendo gli script principali aggiornati.
- Evitare `DROP TABLE` diretti in produzione; preferire migrazioni incrementali.
- Documentare vincoli opzionali (index, unique, check) direttamente nel commit/README.

---

## 🌐 Integrazione con Backend

- Il backend usa la funzione `get_current_tenant_id()` negli statement RLS per garantire isolamento dei tenant.
- Qualsiasi nuova tabella multi-tenant deve replicare il pattern:
  - Colonna `tenant_id` → FK `users.id`.
  - Policy RLS `SELECT`, `INSERT`, `UPDATE`, `DELETE`.
  - Funzione `get_current_tenant_id` riutilizzabile.

---

## 📋 Roadmap DB

- Migrazione per log attività (tabella `task_events` con trigger).
- Indici su `tasks (tenant_id, date_time DESC)` per ottimizzare ordinamento.
- Constraint esclusiva tra `end_time` e `duration_minutes` direttamente lato DB (trigger).
- Script seed demo per ambienti staging.

---

## 📄 Licenza

Parte della suite **My Planner** – schema e policy rilasciati sotto licenza MIT.
