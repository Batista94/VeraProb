import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL || 'http://127.0.0.1:54321'
const supabaseKey = process.env.SUPABASE_KEY || 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'

const supabase = createClient(supabaseUrl, supabaseKey)

async function getJwt() {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: 'master@veraprob.dev',
    password: 'VeraProb@2026',
  })
  
  if (error) {
    console.error('Error signing in:', error.message)
    process.exit(1)
  }
  
  console.log(data.session.access_token)
}

getJwt()
