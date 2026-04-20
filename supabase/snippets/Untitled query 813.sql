-- Verificar se super_admin_users foi populada
SELECT * FROM public.super_admin_users;

-- Verificar GRANT do hook
SELECT grantee, privilege_type 
FROM information_schema.routine_privileges 
WHERE routine_name = 'custom_access_token_hook';
