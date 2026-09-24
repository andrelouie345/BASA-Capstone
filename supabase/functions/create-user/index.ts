// supabase/functions/create-user/index.ts

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
    // Client scoped to the CALLER's own JWT — only used to find out who's calling.
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser()
    if (callerErr || !caller) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Service-role client — the only place the privileged key is used.
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )
///
    const { data: callerProfile, error: profileErr } = await adminClient
      .from('users')
      .select('role, school_id')
      .eq('id', caller.id)
      .single()

    if (profileErr || !callerProfile || !['admin', 'coordinator'].includes(callerProfile.role)) {
      return new Response(JSON.stringify({ error: 'Forbidden: admin or coordinator only' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const callerIsSuperadmin = callerProfile.role === 'admin' && callerProfile.school_id === null

    const { email, full_name, role, school_id, created_by } = await req.json()

    if (!email || !full_name || !role) {
      return new Response(JSON.stringify({ error: 'email, full_name, and role are required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if (!['admin', 'coordinator', 'tutor'].includes(role)) {
      return new Response(JSON.stringify({ error: `Invalid role: ${role}` }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // A requested school_id of null/undefined means "create a superadmin" —
    // only a superadmin creating another admin is allowed to do that.
    if (school_id === null || school_id === undefined) {
      if (!(callerIsSuperadmin && role === 'admin')) {
        return new Response(JSON.stringify({ error: 'school_id is required' }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
    } else if (!callerIsSuperadmin && school_id !== callerProfile.school_id) {
      // School-bound admin/coordinator can only create users within their own school.
      return new Response(JSON.stringify({ error: 'Forbidden: can only create users for your own school' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Step 1: create the Auth account with the shared temp password,
    // flagged so the (future) login flow knows to force a change.
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

    // Step 2: insert the matching profile row
    const { error: insertErr } = await adminClient.from('users').insert({
      id: created.user.id,
      email,
      full_name,
      role,
      school_id: school_id ?? null,
      created_by: created_by ?? caller.id,
    })
///
    if (insertErr) {
      // Roll back the orphaned Auth account if the profile insert fails
      await adminClient.auth.admin.deleteUser(created.user.id)
      return new Response(JSON.stringify({ error: insertErr.message }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ id: created.user.id, email, role }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})