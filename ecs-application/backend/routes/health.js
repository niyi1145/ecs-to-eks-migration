const express = require('express');
const { getPool } = require('../config/database');
const { getRedisClient } = require('../config/redis');

const router = express.Router();

// Health check endpoint
router.get('/', async (req, res) => {
  const healthCheck = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development',
    version: '1.0.0',
    services: {
      api: 'healthy',
      database: 'unknown',
      redis: 'unknown'
    }
  };

  try {
    // Check database connection
    const pool = getPool();
    const dbResult = await pool.query('SELECT NOW()');
    healthCheck.services.database = 'healthy';
    healthCheck.database = {
      connected: true,
      timestamp: dbResult.rows[0].now
    };
  } catch (error) {
    healthCheck.services.database = 'unhealthy';
    healthCheck.database = {
      connected: false,
      error: error.message
    };
  }

  try {
    // Check Redis connection
    const redis = getRedisClient();
    await redis.ping();
    healthCheck.services.redis = 'healthy';
    healthCheck.redis = {
      connected: true,
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    healthCheck.services.redis = 'unhealthy';
    healthCheck.redis = {
      connected: false,
      error: error.message
    };
  }

  // Determine overall health
  const allServicesHealthy = Object.values(healthCheck.services).every(
    status => status === 'healthy'
  );

  healthCheck.status = allServicesHealthy ? 'healthy' : 'unhealthy';

  const statusCode = allServicesHealthy ? 200 : 503;
  res.status(statusCode).json(healthCheck);
});

// Readiness probe
router.get('/ready', async (req, res) => {
  try {
    // Check if all critical services are ready
    const pool = getPool();
    await pool.query('SELECT 1');
    
    const redis = getRedisClient();
    await redis.ping();
    
    res.status(200).json({
      status: 'ready',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(503).json({
      status: 'not ready',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Liveness probe
router.get('/live', (req, res) => {
  res.status(200).json({
    status: 'alive',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

module.exports = router;
