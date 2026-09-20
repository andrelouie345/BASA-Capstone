// supabase/functions/bootstrap-admin/index.ts
// deno-lint-ignore no-import-prefix
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DEFAULT_TEMP_PASSWORD = 'password'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // The entire safety model: this function is wide open, but only
    // does anything while this project has zero users.
    const { count, error: countErr } = await adminClient
      .from('users')
      .select('*', { count: 'exact', head: true })

    if (countErr) {
      return new Response(JSON.stringify({ error: countErr.message }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if ((count ?? 0) > 0) {
      return new Response(JSON.stringify({ error: 'Bootstrap already completed for this project' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { email, full_name } = await req.json()
    if (!email || !full_name) {
      return new Response(JSON.stringify({ error: 'email and full_name are required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      password: DEFAULT_TEMP_PASSWORD,
      email_confirm: true,
      user_metadata: { must_change_password: true },
    })
    if (createErr || !created.user) {
      return new Response(JSON.stringify({ error: createErr?.message ?? 'Auth creation failed' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { error: insertErr } = await adminClient.from('users').insert({
      id: created.user.id,
      email,
      full_name,
      role: 'admin',
      created_by: null,
    })

    if (insertErr) {
      await adminClient.auth.admin.deleteUser(created.user.id)
      return new Response(JSON.stringify({ error: insertErr.message }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ id: created.user.id, email, role: 'admin' }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})