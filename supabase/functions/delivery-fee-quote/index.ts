import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const storeAddress =
  '140 Lê Trọng Tấn, Tây Thạnh, Hồ Chí Minh 700000, Việt Nam'
const quoteLifetimeMs = 15 * 60 * 1000

type RouteQuote = { distanceMeters: number; feeVnd: number }

function feeFor(distanceMeters: number): number {
  const excessMeters = Math.max(distanceMeters - 3000, 0)
  return Math.ceil((excessMeters * 5) / 1000) * 1000
}

async function addressHash(address: string | null): Promise<string | null> {
  if (!address) return null
  const bytes = new TextEncoder().encode(address.trim())
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('')
}

async function driveDistance(
  apiKey: string,
  destination: string,
): Promise<RouteQuote> {
  const response = await fetch(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'routes.distanceMeters',
      },
      body: JSON.stringify({
        origin: { address: storeAddress },
        destination: { address: destination },
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_UNAWARE',
        languageCode: 'vi',
        regionCode: 'VN',
      }),
      signal: AbortSignal.timeout(15000),
    },
  )

  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    console.error('Google Routes API error', response.status, body)
    throw new Error('Không tính được quãng đường đến địa chỉ này.')
  }

  const meters = body?.routes?.[0]?.distanceMeters
  if (!Number.isInteger(meters) || meters < 0) {
    throw new Error('Google Maps không tìm được tuyến đường hợp lệ.')
  }
  return { distanceMeters: meters, feeVnd: feeFor(meters) }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  const respond = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  if (request.method !== 'POST') return respond({ error: 'Method not allowed' }, 405)

  const authorization = request.headers.get('Authorization')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ??
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ??
    Deno.env.get('SUPABASE_SECRET_KEY')
  const mapsApiKey = Deno.env.get('GOOGLE_ROUTES_API_KEY') ??
    Deno.env.get('GOOGLE_MAPS_ROUTES_API_KEY')
  if (!authorization || !supabaseUrl || !anonKey || !serviceRoleKey) {
    return respond({ error: 'Authentication or server configuration is missing.' }, 500)
  }
  if (!mapsApiKey) {
    return respond({ error: 'Server chưa cấu hình dịch vụ tính tuyến đường.' }, 503)
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: userData, error: authError } = await userClient.auth.getUser()
  if (authError || !userData.user) return respond({ error: 'Vui lòng đăng nhập lại.' }, 401)

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch {
    return respond({ error: 'Dữ liệu địa chỉ không hợp lệ.' }, 400)
  }
  const pickupAddress = typeof body.pickupAddress === 'string'
    ? body.pickupAddress.trim()
    : ''
  const deliveryAddress = typeof body.deliveryAddress === 'string'
    ? body.deliveryAddress.trim()
    : ''
  if (pickupAddress.length > 500 || deliveryAddress.length > 500) {
    return respond({ error: 'Địa chỉ quá dài.' }, 400)
  }
  if (!pickupAddress && !deliveryAddress) {
    return respond({ error: 'Cần ít nhất một địa chỉ giao nhận tại nhà.' }, 400)
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const pickupAddressHash = await addressHash(pickupAddress || null)
  const deliveryAddressHash = await addressHash(deliveryAddress || null)
  const now = new Date().toISOString()
  await admin.from('delivery_fee_quotes').delete().lt('expires_at', now)

  // Reuse a live quote for the same user and address pair. This avoids another
  // Google Routes request when a screen rebuilds or the user retries.
  let cachedQuoteQuery = admin
    .from('delivery_fee_quotes')
    .select('id, expires_at, pickup_distance_meters, delivery_distance_meters')
    .eq('auth_user_id', userData.user.id)
    .gt('expires_at', now)
  cachedQuoteQuery = pickupAddressHash
    ? cachedQuoteQuery.eq('pickup_address_hash', pickupAddressHash)
    : cachedQuoteQuery.is('pickup_address_hash', null)
  cachedQuoteQuery = deliveryAddressHash
    ? cachedQuoteQuery.eq('delivery_address_hash', deliveryAddressHash)
    : cachedQuoteQuery.is('delivery_address_hash', null)
  const { data: cachedQuote, error: cacheError } = await cachedQuoteQuery
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (cacheError) {
    console.error('Could not find a reusable delivery fee quote', cacheError)
    return respond({ error: 'Chưa thể kiểm tra báo giá giao nhận. Vui lòng thử lại.' }, 503)
  }
  if (cachedQuote) {
    const pickupDistanceMeters = cachedQuote.pickup_distance_meters
    const deliveryDistanceMeters = cachedQuote.delivery_distance_meters
    const pickupFeeVnd = pickupAddress ? feeFor(pickupDistanceMeters) : 0
    const deliveryFeeVnd = deliveryAddress ? feeFor(deliveryDistanceMeters) : 0
    // Keep quote tokens one-use per checkout while reusing route computation.
    const expiresAt = new Date(Date.now() + quoteLifetimeMs).toISOString()
    const { data: quote, error: insertError } = await admin
      .from('delivery_fee_quotes')
      .insert({
        auth_user_id: userData.user.id,
        pickup_address_hash: pickupAddressHash,
        delivery_address_hash: deliveryAddressHash,
        pickup_distance_meters: pickupDistanceMeters,
        delivery_distance_meters: deliveryDistanceMeters,
        expires_at: expiresAt,
      })
      .select('id, expires_at')
      .single()
    if (insertError) {
      console.error('Could not create a delivery quote from cached routes', insertError)
      return respond({ error: 'Không lưu được báo giá giao nhận.' }, 500)
    }
    return respond({
      quoteId: quote.id,
      expiresAt: quote.expires_at,
      pickupDistanceMeters,
      pickupFeeVnd,
      deliveryDistanceMeters,
      deliveryFeeVnd,
      totalFeeVnd: pickupFeeVnd + deliveryFeeVnd,
    })
  }

  const requestWindowStart = new Date(Date.now() - 60 * 1000).toISOString()
  await admin
    .from('delivery_fee_quote_attempts')
    .delete()
    .lt('created_at', new Date(Date.now() - 2 * 60 * 1000).toISOString())
  const { count, error: rateLimitError } = await admin
    .from('delivery_fee_quote_attempts')
    .select('id', { count: 'exact', head: true })
    .eq('auth_user_id', userData.user.id)
    .gte('created_at', requestWindowStart)
  if (rateLimitError) {
    console.error('Could not check delivery quote rate limit', rateLimitError)
    return respond({ error: 'Chưa thể tính phí giao nhận. Vui lòng thử lại.' }, 503)
  }
  if ((count ?? 0) >= 8) {
    return respond({ error: 'Bạn yêu cầu báo giá quá nhanh. Vui lòng chờ một phút.' }, 429)
  }
  const { error: attemptError } = await admin
    .from('delivery_fee_quote_attempts')
    .insert({ auth_user_id: userData.user.id })
  if (attemptError) {
    console.error('Could not record delivery quote request', attemptError)
    return respond({ error: 'Chưa thể tính phí giao nhận. Vui lòng thử lại.' }, 503)
  }
  try {
    let pickup: RouteQuote | null = null
    let delivery: RouteQuote | null = null
    if (pickupAddress && deliveryAddress && pickupAddress === deliveryAddress) {
      pickup = delivery = await driveDistance(mapsApiKey, pickupAddress)
    } else {
      [pickup, delivery] = await Promise.all([
        pickupAddress ? driveDistance(mapsApiKey, pickupAddress) : null,
        deliveryAddress ? driveDistance(mapsApiKey, deliveryAddress) : null,
      ])
    }
    const expiresAt = new Date(Date.now() + quoteLifetimeMs).toISOString()
    const { data: quote, error: insertError } = await admin
      .from('delivery_fee_quotes')
      .insert({
        auth_user_id: userData.user.id,
        pickup_address_hash: pickupAddressHash,
        delivery_address_hash: deliveryAddressHash,
        pickup_distance_meters: pickup?.distanceMeters ?? 0,
        delivery_distance_meters: delivery?.distanceMeters ?? 0,
        expires_at: expiresAt,
      })
      .select('id, expires_at')
      .single()
    if (insertError) {
      console.error('Could not save delivery fee quote', insertError)
      return respond({ error: 'Không lưu được báo giá giao nhận.' }, 500)
    }

    return respond({
      quoteId: quote.id,
      expiresAt: quote.expires_at,
      pickupDistanceMeters: pickup?.distanceMeters ?? 0,
      pickupFeeVnd: pickup?.feeVnd ?? 0,
      deliveryDistanceMeters: delivery?.distanceMeters ?? 0,
      deliveryFeeVnd: delivery?.feeVnd ?? 0,
      totalFeeVnd: (pickup?.feeVnd ?? 0) + (delivery?.feeVnd ?? 0),
    })
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : 'Không tính được phí giao nhận.'
    return respond({ error: message }, 422)
  }
})
