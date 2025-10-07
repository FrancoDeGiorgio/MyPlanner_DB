-- Questa policy garantisce che un utente (tenant) possa accedere 
-- e modificare SOLO le attività associate al proprio ID.

-- 1. Attivazione della Row-Level Security (RLS) sulla tabella 'tasks'
-- CRITICO: Senza questo, le policy non funzionano!
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- 2. Creazione di una funzione di utilità per estrarre l'ID Tenant
-- Questa funzione legge il 'name_user' dal claim 'sub' del JWT 
-- (che sarà iniettato da FastAPI) e restituisce l'ID UUID corrispondente.
CREATE OR REPLACE FUNCTION get_current_tenant_id()
RETURNS uuid AS $$
  SELECT id 
  FROM users 
  WHERE name_user = current_setting('request.jwt.claim.sub', TRUE)
$$ LANGUAGE sql STABLE;

-- 3. Policy di Selezione (READ)
-- Permette agli utenti di LEGGERE solo le righe dove il tenant_id della riga 
-- è uguale all'ID dell'utente che sta eseguendo la query.
CREATE POLICY "Tenants can only read their own tasks"
ON tasks FOR SELECT TO authenticated
USING (tenant_id = get_current_tenant_id());

-- 4. Policy di Inserimento (CREATE)
-- Permette di INSERIRE una nuova attività, ma solo se l'utente sta cercando di
-- inserire il PROPRIO ID come tenant_id.
CREATE POLICY "Tenants can insert their own tasks"
ON tasks FOR INSERT TO authenticated
WITH CHECK (tenant_id = get_current_tenant_id());

-- 5. Policy di Aggiornamento (UPDATE)
-- Permette l'aggiornamento, assicurandosi che l'utente sia il proprietario (USING) 
-- e che non stia cercando di cambiare il tenant_id (WITH CHECK).
CREATE POLICY "Tenants can update their own tasks"
ON tasks FOR UPDATE TO authenticated
USING (tenant_id = get_current_tenant_id())
WITH CHECK (tenant_id = get_current_tenant_id());

-- 6. Policy di Cancellazione (DELETE)
-- Permette la cancellazione solo se la riga appartiene all'utente.
CREATE POLICY "Tenants can delete their own tasks"
ON tasks FOR DELETE TO authenticated
USING (tenant_id = get_current_tenant_id());
