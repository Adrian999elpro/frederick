# Pruebas SQL (opcionales, solo desarrollo)
Verifican registro, RLS, permisos, voto único/secreto y resultados contra un PostgreSQL local
con un esquema `auth`/`storage` simulado. **No ejecutar en tu proyecto Supabase real.**

    createdb t
    psql -d t -f 00_stubs_supabase.sql
    psql -d t -f ../migrations/0001_auth_core.sql
    psql -d t -f ../migrations/0002_elections.sql
    psql -d t -f 01_auth_and_elections_test.sql     # al final: pasaron = 51, fallaron = 0
