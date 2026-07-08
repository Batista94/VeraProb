-- update permission descriptions from 'do tenant' to 'da organização'

UPDATE public.tenant_permissions
   SET description = 'Visualizar dados financeiros da organização'
 WHERE key = 'financial:read';

UPDATE public.tenant_permissions
   SET description = 'Visualizar contratos da organização'
 WHERE key = 'contracts:read';
