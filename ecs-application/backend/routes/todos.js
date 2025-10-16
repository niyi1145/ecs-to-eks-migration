const express = require('express');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { getPool } = require('../config/database');
const { cache } = require('../config/redis');

const router = express.Router();

// Middleware to authenticate JWT token
const authenticateToken = async (req, res, next) => {
  try {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
      return res.status(401).json({ error: 'Access token required' });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key');
    
    // Check if session exists in cache
    const session = await cache.get(`session:${decoded.userId}`);
    if (!session) {
      return res.status(401).json({ error: 'Session expired' });
    }

    req.user = session;
    next();
  } catch (error) {
    return res.status(403).json({ error: 'Invalid token' });
  }
};

// Apply authentication middleware to all routes
router.use(authenticateToken);

// Get all todos for the authenticated user
router.get('/', async (req, res) => {
  try {
    const { page = 1, limit = 10, completed, priority } = req.query;
    const offset = (page - 1) * limit;
    
    const pool = getPool();
    let query = 'SELECT * FROM todos WHERE user_id = $1';
    const queryParams = [req.user.userId];
    let paramCount = 1;

    // Add filters
    if (completed !== undefined) {
      paramCount++;
      query += ` AND completed = $${paramCount}`;
      queryParams.push(completed === 'true');
    }

    if (priority) {
      paramCount++;
      query += ` AND priority = $${paramCount}`;
      queryParams.push(priority);
    }

    // Add ordering and pagination
    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    queryParams.push(parseInt(limit), offset);

    const result = await pool.query(query, queryParams);

    // Get total count for pagination
    let countQuery = 'SELECT COUNT(*) FROM todos WHERE user_id = $1';
    const countParams = [req.user.userId];
    let countParamCount = 1;

    if (completed !== undefined) {
      countParamCount++;
      countQuery += ` AND completed = $${countParamCount}`;
      countParams.push(completed === 'true');
    }

    if (priority) {
      countParamCount++;
      countQuery += ` AND priority = $${countParamCount}`;
      countParams.push(priority);
    }

    const countResult = await pool.query(countQuery, countParams);
    const totalCount = parseInt(countResult.rows[0].count);

    res.json({
      todos: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / limit)
      }
    });
  } catch (error) {
    console.error('Get todos error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get a specific todo
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const pool = getPool();

    const result = await pool.query(
      'SELECT * FROM todos WHERE id = $1 AND user_id = $2',
      [id, req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Get todo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create a new todo
router.post('/', async (req, res) => {
  try {
    const { title, description, priority = 'medium', due_date } = req.body;

    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

    if (priority && !['low', 'medium', 'high'].includes(priority)) {
      return res.status(400).json({ 
        error: 'Priority must be one of: low, medium, high' 
      });
    }

    const pool = getPool();
    const result = await pool.query(
      'INSERT INTO todos (user_id, title, description, priority, due_date) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [req.user.userId, title, description, priority, due_date]
    );

    // Invalidate user's todo cache
    await cache.del(`todos:${req.user.userId}`);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Create todo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update a todo
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { title, description, completed, priority, due_date } = req.body;

    if (priority && !['low', 'medium', 'high'].includes(priority)) {
      return res.status(400).json({ 
        error: 'Priority must be one of: low, medium, high' 
      });
    }

    const pool = getPool();

    // Check if todo exists and belongs to user
    const existingTodo = await pool.query(
      'SELECT * FROM todos WHERE id = $1 AND user_id = $2',
      [id, req.user.userId]
    );

    if (existingTodo.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }

    // Build update query dynamically
    const updates = [];
    const values = [];
    let paramCount = 0;

    if (title !== undefined) {
      paramCount++;
      updates.push(`title = $${paramCount}`);
      values.push(title);
    }

    if (description !== undefined) {
      paramCount++;
      updates.push(`description = $${paramCount}`);
      values.push(description);
    }

    if (completed !== undefined) {
      paramCount++;
      updates.push(`completed = $${paramCount}`);
      values.push(completed);
    }

    if (priority !== undefined) {
      paramCount++;
      updates.push(`priority = $${paramCount}`);
      values.push(priority);
    }

    if (due_date !== undefined) {
      paramCount++;
      updates.push(`due_date = $${paramCount}`);
      values.push(due_date);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    // Add updated_at and WHERE clause
    paramCount++;
    updates.push(`updated_at = CURRENT_TIMESTAMP`);
    values.push(id);
    paramCount++;
    values.push(req.user.userId);

    const query = `
      UPDATE todos 
      SET ${updates.join(', ')} 
      WHERE id = $${paramCount - 1} AND user_id = $${paramCount}
      RETURNING *
    `;

    const result = await pool.query(query, values);

    // Invalidate user's todo cache
    await cache.del(`todos:${req.user.userId}`);

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Update todo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete a todo
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const pool = getPool();

    const result = await pool.query(
      'DELETE FROM todos WHERE id = $1 AND user_id = $2 RETURNING *',
      [id, req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }

    // Invalidate user's todo cache
    await cache.del(`todos:${req.user.userId}`);

    res.json({ message: 'Todo deleted successfully' });
  } catch (error) {
    console.error('Delete todo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Toggle todo completion status
router.patch('/:id/toggle', async (req, res) => {
  try {
    const { id } = req.params;
    const pool = getPool();

    const result = await pool.query(
      'UPDATE todos SET completed = NOT completed, updated_at = CURRENT_TIMESTAMP WHERE id = $1 AND user_id = $2 RETURNING *',
      [id, req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }

    // Invalidate user's todo cache
    await cache.del(`todos:${req.user.userId}`);

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Toggle todo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get todo statistics
router.get('/stats/summary', async (req, res) => {
  try {
    const pool = getPool();

    const result = await pool.query(`
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE completed = true) as completed,
        COUNT(*) FILTER (WHERE completed = false) as pending,
        COUNT(*) FILTER (WHERE priority = 'high') as high_priority,
        COUNT(*) FILTER (WHERE priority = 'medium') as medium_priority,
        COUNT(*) FILTER (WHERE priority = 'low') as low_priority
      FROM todos 
      WHERE user_id = $1
    `, [req.user.userId]);

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Get stats error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
