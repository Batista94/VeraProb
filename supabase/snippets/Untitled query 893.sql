UPDATE contracts 
SET status = 'active', version = 2 
WHERE id = '4db71084-9533-4fc9-ac16-b67fc9059b3c' 
RETURNING id, previous_hash, current_hash;