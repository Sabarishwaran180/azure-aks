const express = require('express');
const mongoose = require('mongoose');
const Redis = require('ioredis');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3002;
app.use(express.json());

// ── Prometheus ─────────────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const cacheHits = new promClient.Counter({
  name: 'product_cache_hits_total',
  help: 'Redis cache hits for products',
  registers: [register],
});
const cacheMisses = new promClient.Counter({
  name: 'product_cache_misses_total',
  help: 'Redis cache misses for products',
  registers: [register],
});

// ── MongoDB connection ─────────────────────────────────────
const MONGO_URI = `mongodb://${process.env.MONGO_USER}:${process.env.MONGO_PASSWORD}@` +
  `${process.env.MONGO_HOST}:${process.env.MONGO_PORT}/${process.env.MONGO_DB}?authSource=admin`;

mongoose.connect(MONGO_URI, {
  maxPoolSize: 10,
  serverSelectionTimeoutMS: 5000,
}).catch(err => console.error('MongoDB connection error:', err));

// ── Redis client ───────────────────────────────────────────
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD,
  retryStrategy: (times) => Math.min(times * 50, 2000),
  maxRetriesPerRequest: 3,
});

// ── Product Schema ─────────────────────────────────────────
const productSchema = new mongoose.Schema({
  name: { type: String, required: true, index: true },
  description: String,
  price: { type: Number, required: true, min: 0 },
  category: { type: String, required: true, index: true },
  stock: { type: Number, default: 0, min: 0 },
  images: [String],
  tags: [String],
  isActive: { type: Boolean, default: true },
}, { timestamps: true });

productSchema.index({ name: 'text', description: 'text' });
const Product = mongoose.model('Product', productSchema);

// ── Routes ─────────────────────────────────────────────────
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'product-service' }));
app.get('/readyz', async (req, res) => {
  const dbState = mongoose.connection.readyState === 1;
  if (!dbState) return res.status(503).json({ status: 'not ready' });
  res.json({ status: 'ready' });
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// List products (with Redis cache)
app.get('/', async (req, res) => {
  const { category, page = 1, limit = 20, search } = req.query;
  const cacheKey = `products:${category || 'all'}:${page}:${limit}:${search || ''}`;
  try {
    const cached = await redis.get(cacheKey);
    if (cached) {
      cacheHits.inc();
      return res.json(JSON.parse(cached));
    }
    cacheMisses.inc();
    const filter = { isActive: true };
    if (category) filter.category = category;
    if (search) filter.$text = { $search: search };
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [products, total] = await Promise.all([
      Product.find(filter).skip(skip).limit(parseInt(limit)).lean(),
      Product.countDocuments(filter),
    ]);
    const response = { products, total, page: parseInt(page), pages: Math.ceil(total / limit) };
    await redis.setex(cacheKey, parseInt(process.env.CACHE_TTL) || 300, JSON.stringify(response));
    res.json(response);
  } catch (err) {
    console.error('List products error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get single product
app.get('/:id', async (req, res) => {
  const cacheKey = `product:${req.params.id}`;
  try {
    const cached = await redis.get(cacheKey);
    if (cached) { cacheHits.inc(); return res.json(JSON.parse(cached)); }
    cacheMisses.inc();
    const product = await Product.findById(req.params.id).lean();
    if (!product) return res.status(404).json({ error: 'Product not found' });
    await redis.setex(cacheKey, 300, JSON.stringify(product));
    res.json(product);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create product
app.post('/', async (req, res) => {
  try {
    const product = new Product(req.body);
    await product.save();
    await redis.del('products:all:1:20:');
    res.status(201).json(product);
  } catch (err) {
    if (err.name === 'ValidationError') return res.status(400).json({ error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update stock (called by order service)
app.patch('/:id/stock', async (req, res) => {
  try {
    const { quantity } = req.body;
    const product = await Product.findByIdAndUpdate(
      req.params.id,
      { $inc: { stock: -quantity } },
      { new: true, runValidators: true }
    );
    if (!product) return res.status(404).json({ error: 'Product not found' });
    await redis.del(`product:${req.params.id}`);
    res.json({ id: product._id, stock: product.stock });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

const server = app.listen(PORT, '0.0.0.0', () =>
  console.log(`Product Service running on port ${PORT}`)
);

process.on('SIGTERM', () => {
  server.close(() => { mongoose.connection.close(); redis.quit(); process.exit(0); });
});
