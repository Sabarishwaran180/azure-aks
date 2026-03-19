const express = require('express');
const amqp = require('amqplib');
const nodemailer = require('nodemailer');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3005;
app.use(express.json());

// ── Prometheus ─────────────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const notificationsSent = new promClient.Counter({
  name: 'notifications_sent_total',
  help: 'Total notifications sent',
  labelNames: ['type', 'status'],
  registers: [register],
});
const queueDepth = new promClient.Gauge({
  name: 'rabbitmq_queue_depth',
  help: 'Current RabbitMQ queue depth (used by KEDA)',
  labelNames: ['queue'],
  registers: [register],
});

// ── Email transporter ──────────────────────────────────────
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: parseInt(process.env.SMTP_PORT) || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD,    // from Key Vault
  },
});

// ── RabbitMQ Consumer ──────────────────────────────────────
async function startConsuming() {
  try {
    const conn = await amqp.connect(
      `amqp://${process.env.RABBITMQ_USER}:${process.env.RABBITMQ_PASSWORD}@` +
      `${process.env.RABBITMQ_HOST}:${process.env.RABBITMQ_PORT}/`
    );
    const channel = await conn.createChannel();
    channel.prefetch(10);  // Process max 10 messages at a time

    // Consume ORDER queue
    await channel.assertQueue(process.env.ORDER_QUEUE, { durable: true });
    channel.consume(process.env.ORDER_QUEUE, async (msg) => {
      if (!msg) return;
      try {
        const order = JSON.parse(msg.content.toString());
        await sendOrderConfirmationEmail(order);
        notificationsSent.inc({ type: 'order_confirmation', status: 'sent' });
        channel.ack(msg);
      } catch (err) {
        console.error('Failed to process order notification:', err);
        notificationsSent.inc({ type: 'order_confirmation', status: 'failed' });
        channel.nack(msg, false, false);  // Dead-letter the message
      }
    });

    // Consume PAYMENT queue
    await channel.assertQueue(process.env.PAYMENT_QUEUE, { durable: true });
    channel.consume(process.env.PAYMENT_QUEUE, async (msg) => {
      if (!msg) return;
      try {
        const payment = JSON.parse(msg.content.toString());
        await sendPaymentConfirmationEmail(payment);
        notificationsSent.inc({ type: 'payment_confirmation', status: 'sent' });
        channel.ack(msg);
      } catch (err) {
        notificationsSent.inc({ type: 'payment_confirmation', status: 'failed' });
        channel.nack(msg, false, false);
      }
    });

    console.log('Notification Service consuming from RabbitMQ');
  } catch (err) {
    console.error('RabbitMQ connection failed, retrying...', err.message);
    setTimeout(startConsuming, 5000);
  }
}

// ── Email templates ────────────────────────────────────────
async function sendOrderConfirmationEmail(order) {
  await transporter.sendMail({
    from: process.env.FROM_EMAIL,
    to: order.userEmail || `user-${order.userId}@example.com`,
    subject: `Order Confirmation #${order.orderId.substring(0, 8)}`,
    html: `
      <h2>Thank you for your order!</h2>
      <p>Order ID: <strong>${order.orderId}</strong></p>
      <p>Total: <strong>$${order.total}</strong></p>
      <p>We'll ship your items soon.</p>
    `,
  });
}

async function sendPaymentConfirmationEmail(payment) {
  await transporter.sendMail({
    from: process.env.FROM_EMAIL,
    to: `user-${payment.userId}@example.com`,
    subject: `Payment ${payment.status === 'succeeded' ? 'Successful' : 'Failed'}`,
    html: `
      <h2>Payment ${payment.status === 'succeeded' ? '✅ Successful' : '❌ Failed'}</h2>
      <p>Order: <strong>${payment.orderId}</strong></p>
      <p>Amount: <strong>$${payment.amount}</strong></p>
    `,
  });
}

// ── HTTP server ────────────────────────────────────────────
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'notification-service' }));
app.get('/readyz', (req, res) => res.json({ status: 'ready' }));
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Send a direct notification (for testing)
app.post('/send', async (req, res) => {
  const { to, subject, body } = req.body;
  try {
    await transporter.sendMail({ from: process.env.FROM_EMAIL, to, subject, html: body });
    res.json({ sent: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`Notification Service running on port ${PORT}`);
  startConsuming();
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
