const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3001;
app.use(express.json());

// ── Prometheus metrics ─────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const loginCounter = new promClient.Counter({
  name: 'user_logins_total',
  help: 'Total login attempts',
  labelNames: ['status'],
  registers: [register],
});

// ── Database connection pool ───────────────────────────────
const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,   // Injected from Key Vault
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => {
  console.error('Unexpected DB pool error', err);
});

// ── Routes ─────────────────────────────────────────────────
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'user-service' }));
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready', db: 'connected' });
  } catch {
    res.status(503).json({ status: 'not ready', db: 'disconnected' });
  }
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Register
app.post('/register', async (req, res) => {
  const { email, password, name } = req.body;
  if (!email || !password || !name)
    return res.status(400).json({ error: 'email, password, name required' });
  try {
    const existing = await pool.query('SELECT id FROM users WHERE email=$1', [email]);
    if (existing.rows.length > 0)
      return res.status(409).json({ error: 'Email already registered' });
    const hash = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS) || 12);
    const result = await pool.query(
      'INSERT INTO users (email, password_hash, name, created_at) VALUES ($1,$2,$3,NOW()) RETURNING id, email, name',
      [email, hash, name]
    );
    res.status(201).json({ user: result.rows[0] });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login
app.post('/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);
    if (!result.rows.length || !(await bcrypt.compare(password, result.rows[0].password_hash))) {
      loginCounter.inc({ status: 'failed' });
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    const user = result.rows[0];
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRY || '15m' }
    );
    const refreshToken = jwt.sign(
      { userId: user.id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.REFRESH_TOKEN_EXPIRY || '7d' }
    );
    await pool.query(
      'UPDATE users SET last_login=NOW() WHERE id=$1', [user.id]
    );
    loginCounter.inc({ status: 'success' });
    res.json({ accessToken, refreshToken, user: { id: user.id, email: user.email, name: user.name } });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get user profile
app.get('/profile/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, email, name, created_at, last_login FROM users WHERE id=$1',
      [req.params.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'User not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Graceful shutdown
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`User Service running on port ${PORT}`);
  // Create users table on startup
  pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      name VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      last_login TIMESTAMP
    )
  `).catch(console.error);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    pool.end();
    process.exit(0);
  });
});
