const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const morgan = require('morgan');
const cors = require('cors');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3000;

// ── Prometheus metrics ─────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

// ── Middleware ─────────────────────────────────────────────
app.use(helmet());
app.use(express.json({ limit: '10mb' }));
app.use(morgan('combined'));
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Rate limiting — prevents abuse
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 60000,
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
app.use('/api/', limiter);

// Metrics middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    end({ method: req.method, route: req.path, status_code: res.statusCode });
    httpRequestsTotal.inc({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});

// ── Health / Readiness endpoints ───────────────────────────
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'api-gateway' }));
app.get('/readyz', async (req, res) => {
  // Check if downstream services are reachable
  res.json({ status: 'ready' });
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ── Service Routes (Proxy to microservices) ────────────────
const proxyOptions = (target) => ({
  target,
  changeOrigin: true,
  pathRewrite: { '^/api/v1/[^/]+': '' },
  on: {
    error: (err, req, res) => {
      console.error(`Proxy error to ${target}:`, err.message);
      res.status(503).json({ error: 'Service temporarily unavailable' });
    },
  },
});

// Route: /api/v1/users/* → User Service
app.use('/api/v1/users',
  createProxyMiddleware(proxyOptions(process.env.USER_SERVICE_URL)));

// Route: /api/v1/auth/* → User Service
app.use('/api/v1/auth',
  createProxyMiddleware(proxyOptions(process.env.USER_SERVICE_URL)));

// Route: /api/v1/products/* → Product Service
app.use('/api/v1/products',
  createProxyMiddleware(proxyOptions(process.env.PRODUCT_SERVICE_URL)));

// Route: /api/v1/orders/* → Order Service
app.use('/api/v1/orders',
  createProxyMiddleware(proxyOptions(process.env.ORDER_SERVICE_URL)));

// Route: /api/v1/payments/* → Payment Service
app.use('/api/v1/payments',
  createProxyMiddleware(proxyOptions(process.env.PAYMENT_SERVICE_URL)));

// Route: /api/v1/notifications/* → Notification Service
app.use('/api/v1/notifications',
  createProxyMiddleware(proxyOptions(process.env.NOTIFICATION_SERVICE_URL)));

// ── 404 handler ────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.path} not found` });
});

// ── Error handler ──────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`API Gateway running on port ${PORT}`);
});

module.exports = app;
