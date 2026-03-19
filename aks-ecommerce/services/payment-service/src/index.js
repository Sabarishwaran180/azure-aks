const express = require('express');
const Stripe = require('stripe');
const { Pool } = require('pg');
const amqp = require('amqplib');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3004;

// ── Stripe webhook needs raw body ──────────────────────────
app.use('/webhook', express.raw({ type: 'application/json' }));
app.use(express.json());

// ── Prometheus ─────────────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const paymentsTotal = new promClient.Counter({
  name: 'payments_total',
  help: 'Total payment attempts',
  labelNames: ['status'],
  registers: [register],
});
const paymentAmount = new promClient.Histogram({
  name: 'payment_amount_dollars',
  help: 'Payment amounts in dollars',
  buckets: [10, 25, 50, 100, 250, 500, 1000],
  registers: [register],
});

// ── Stripe client (API key from Key Vault) ─────────────────
const stripe = new Stripe(process.env.STRIPE_API_KEY, { apiVersion: '2024-04-10' });

// ── Database ───────────────────────────────────────────────
const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 10,
});

// ── RabbitMQ publisher ─────────────────────────────────────
let channel;
async function connectRabbitMQ() {
  try {
    const conn = await amqp.connect(
      `amqp://${process.env.RABBITMQ_USER}:${process.env.RABBITMQ_PASSWORD}@` +
      `${process.env.RABBITMQ_HOST}:${process.env.RABBITMQ_PORT}/`
    );
    channel = await conn.createChannel();
    await channel.assertQueue(process.env.PAYMENT_QUEUE, { durable: true });
  } catch (err) {
    setTimeout(connectRabbitMQ, 5000);
  }
}
connectRabbitMQ();

// ── Routes ─────────────────────────────────────────────────
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'payment-service' }));
app.get('/readyz', async (req, res) => {
  try { await pool.query('SELECT 1'); res.json({ status: 'ready' }); }
  catch { res.status(503).json({ status: 'not ready' }); }
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Create payment intent
app.post('/create-intent', async (req, res) => {
  const { orderId, amount, currency = 'usd', userId } = req.body;
  if (!orderId || !amount) return res.status(400).json({ error: 'orderId and amount required' });
  try {
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100), // convert to cents
      currency,
      metadata: { orderId, userId },
      automatic_payment_methods: { enabled: true },
    });
    await pool.query(
      `INSERT INTO payments (order_id, stripe_payment_intent_id, amount, currency, status, created_at)
       VALUES ($1, $2, $3, $4, 'pending', NOW())`,
      [orderId, paymentIntent.id, amount, currency]
    );
    paymentsTotal.inc({ status: 'initiated' });
    res.json({ clientSecret: paymentIntent.client_secret, paymentIntentId: paymentIntent.id });
  } catch (err) {
    console.error('Payment intent error:', err);
    res.status(500).json({ error: 'Payment initialization failed' });
  }
});

// Stripe webhook handler
app.post('/webhook', async (req, res) => {
  const sig = req.headers['stripe-signature'];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    return res.status(400).json({ error: `Webhook Error: ${err.message}` });
  }

  if (event.type === 'payment_intent.succeeded') {
    const { id, metadata, amount } = event.data.object;
    await pool.query(
      `UPDATE payments SET status='succeeded', updated_at=NOW() WHERE stripe_payment_intent_id=$1`,
      [id]
    );
    paymentsTotal.inc({ status: 'succeeded' });
    paymentAmount.observe(amount / 100);
    if (channel) {
      channel.sendToQueue(
        process.env.PAYMENT_QUEUE,
        Buffer.from(JSON.stringify({ orderId: metadata.orderId, userId: metadata.userId, status: 'succeeded', amount: amount / 100 })),
        { persistent: true }
      );
    }
  } else if (event.type === 'payment_intent.payment_failed') {
    paymentsTotal.inc({ status: 'failed' });
    const { id } = event.data.object;
    await pool.query(
      `UPDATE payments SET status='failed', updated_at=NOW() WHERE stripe_payment_intent_id=$1`,
      [id]
    );
  }
  res.json({ received: true });
});

const server = app.listen(PORT, '0.0.0.0', async () => {
  console.log(`Payment Service running on port ${PORT}`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS payments (
      id SERIAL PRIMARY KEY,
      order_id UUID NOT NULL,
      stripe_payment_intent_id VARCHAR(255) UNIQUE,
      amount DECIMAL(10,2) NOT NULL,
      currency VARCHAR(10) DEFAULT 'usd',
      status VARCHAR(50) DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    )
  `).catch(console.error);
});

process.on('SIGTERM', () => server.close(() => { pool.end(); process.exit(0); }));
