const { createClient } = require('redis');

let redisClient;

const connectRedis = async () => {
  try {
    const config = {
      host: process.env.REDIS_HOST || 'localhost',
      port: process.env.REDIS_PORT || 6379,
      password: process.env.REDIS_PASSWORD || undefined,
      retry_strategy: (options) => {
        if (options.error && options.error.code === 'ECONNREFUSED') {
          return new Error('Redis server connection refused');
        }
        if (options.total_retry_time > 1000 * 60 * 60) {
          return new Error('Retry time exhausted');
        }
        if (options.attempt > 10) {
          return undefined;
        }
        return Math.min(options.attempt * 100, 3000);
      }
    };

    redisClient = createClient(config);

    redisClient.on('error', (err) => {
      console.error('❌ Redis Client Error:', err);
    });

    redisClient.on('connect', () => {
      console.log('🔗 Redis Client Connected');
    });

    redisClient.on('ready', () => {
      console.log('✅ Redis Client Ready');
    });

    redisClient.on('end', () => {
      console.log('🔌 Redis Client Disconnected');
    });

    await redisClient.connect();
    return redisClient;
  } catch (error) {
    console.error('❌ Redis connection failed:', error);
    throw error;
  }
};

const getRedisClient = () => {
  if (!redisClient) {
    throw new Error('Redis not initialized. Call connectRedis() first.');
  }
  return redisClient;
};

const closeRedis = async () => {
  if (redisClient) {
    await redisClient.quit();
    console.log('🔌 Redis connection closed');
  }
};

// Cache helper functions
const cache = {
  async get(key) {
    try {
      const client = getRedisClient();
      const value = await client.get(key);
      return value ? JSON.parse(value) : null;
    } catch (error) {
      console.error('Cache get error:', error);
      return null;
    }
  },

  async set(key, value, ttl = 3600) {
    try {
      const client = getRedisClient();
      await client.setEx(key, ttl, JSON.stringify(value));
    } catch (error) {
      console.error('Cache set error:', error);
    }
  },

  async del(key) {
    try {
      const client = getRedisClient();
      await client.del(key);
    } catch (error) {
      console.error('Cache delete error:', error);
    }
  },

  async exists(key) {
    try {
      const client = getRedisClient();
      return await client.exists(key);
    } catch (error) {
      console.error('Cache exists error:', error);
      return false;
    }
  }
};

module.exports = {
  connectRedis,
  getRedisClient,
  closeRedis,
  cache
};
