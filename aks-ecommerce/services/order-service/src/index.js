const express = require('express');
const { Pool } = require('pg');
const Redis = require('ioredis');
const amqp = require('amqplib');
const { v4: uuidv4 } = require('uuid');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3003;
app.use(express.json());

// ── Prometheus ─────────────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const ordersCreated = new promClient.Counter({
  name: 'orders_created_total',
  help: 'Total orders created',
  labelNames: ['status'],
  registers: [register],
});

// ── Database pool ──────────────────────────────────────────
const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20,
});

// ── Redis ──────────────────────────────────────────────────
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD,
});

// ── RabbitMQ publisher ─────────────────────────────────────
let channel;
async function connectRabbitMQ() {
  try {
    const conn = await amqp.connect(
      `amqp://${process.env.RABBITMQ_USER}:${process.env.RABBITMQ_PASSWORD}@` +
      `${process.env.RABBITMQ_HOST}:${process.env.RABBITMQ_PORT}${process.env.RABBITMQ_VHOST}`
    );
    channel = await conn.createChannel();
    await channel.assertQueue(process.env.ORDER_QUEUE, { durable: true });
    console.log('RabbitMQ connected');
  } catch (err) {
    console.error('RabbitMQ connection failed, retrying in 5s...', err.message);
    setTimeout(connectRabbitMQ, 5000);
  }
}
connectRabbitMQ();

// ── Routes ─────────────────────────────────────────────────
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'order-service' }));
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready', db: 'connected', mq: channel ? 'connected' : 'disconnected' });
  } catch {
    res.status(503).json({ status: 'not ready' });
  }
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Create order
app.post('/', async (req, res) => {
  const { userId, items, shippingAddress } = req.body;
  if (!userId || !items?.length) return res.status(400).json({ error: 'userId and items required' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const orderId = uuidv4();
    const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

    await client.query(
      `INSERT INTO orders (id, user_id, status, total, shipping_address, created_at)
       VALUES ($1, $2, 'pending', $3, $4, NOW())`,
      [orderId, userId, total, JSON.stringify(shippingAddress)]
    );

    for (const item of items) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, price)
         VALUES ($1, $2, $3, $4)`,
        [orderId, item.productId, item.quantity, item.price]
      );
    }

    await client.query('COMMIT');
    ordersCreated.inc({ status: 'created' });

    // Invalidate user orders cache
    await redis.del(`orders:user:${userId}`);

    // Publish to RabbitMQ for notification/payment processing
    if (channel) {
      channel.sendToQueue(
        process.env.ORDER_QUEUE,
        Buffer.from(JSON.stringify({ orderId, userId, total, items })),
        { persistent: true, messageId: orderId }
      );
    }

    res.status(201).json({ orderId, status: 'pending', total });
  } catch (err) {
    await client.query('ROLLBACK');
    ordersCreated.inc({ status: 'failed' });
    console.error('Create order error:', err);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// Get user orders (with Redis cache)
app.get('/user/:userId', async (req, res) => {
  const cacheKey = `orders:user:${req.params.userId}`;
  try {
    const cached = await redis.get(cacheKey);
    if (cached) return res.json(JSON.parse(cached));
    const result = await pool.query(
      `SELECT o.*, json_agg(oi.*) AS items
       FROM orders o
       LEFT JOIN order_items oi ON o.id = oi.order_id
       WHERE o.user_id=$1
       GROUP BY o.id
       ORDER BY o.created_at DESC`,
      [req.params.userId]
    );
    await redis.setex(cacheKey, 60, JSON.stringify(result.rows));
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Initialize DB tables
const server = app.listen(PORT, '0.0.0.0', async () => {
  console.log(`Order Service running on port ${PORT}`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id UUID PRIMARY KEY,
      user_id INTEGER NOT NULL,
      status VARCHAR(50) DEFAULT 'pending',
      total DECIMAL(10,2) NOT NULL,
      shipping_address JSONB,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS order_items (
      id SERIAL PRIMARY KEY,
      order_id UUID REFERENCES orders(id),
      product_id VARCHAR(255) NOT NULL,
      quantity INTEGER NOT NULL,
      price DECIMAL(10,2) NOT NULL
    );
  `).catch(console.error);
});

process.on('SIGTERM', () => {
  server.close(() => { pool.end(); redis.quit(); process.exit(0); });
});
