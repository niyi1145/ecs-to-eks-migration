#!/usr/bin/env python3
"""
Data Migration Script for ECS to EKS Migration
Handles database and cache data migration
"""

import os
import sys
import json
import time
import psycopg2
import redis
import argparse
from typing import Dict, List, Any
from datetime import datetime

class DataMigrator:
    def __init__(self, source_config: Dict, target_config: Dict):
        self.source_config = source_config
        self.target_config = target_config
        self.migration_log = []
        
    def log(self, message: str, level: str = "INFO"):
        """Log migration events"""
        timestamp = datetime.now().isoformat()
        log_entry = {
            "timestamp": timestamp,
            "level": level,
            "message": message
        }
        self.migration_log.append(log_entry)
        print(f"[{level}] {timestamp}: {message}")
    
    def connect_database(self, config: Dict) -> psycopg2.extensions.connection:
        """Connect to PostgreSQL database"""
        try:
            conn = psycopg2.connect(
                host=config['host'],
                port=config['port'],
                database=config['database'],
                user=config['user'],
                password=config['password']
            )
            return conn
        except Exception as e:
            self.log(f"Database connection failed: {e}", "ERROR")
            raise
    
    def connect_redis(self, config: Dict) -> redis.Redis:
        """Connect to Redis cache"""
        try:
            r = redis.Redis(
                host=config['host'],
                port=config['port'],
                password=config.get('password'),
                decode_responses=True
            )
            # Test connection
            r.ping()
            return r
        except Exception as e:
            self.log(f"Redis connection failed: {e}", "ERROR")
            raise
    
    def migrate_database_schema(self):
        """Migrate database schema from ECS to EKS"""
        self.log("Starting database schema migration...")
        
        try:
            # Connect to source database
            source_conn = self.connect_database(self.source_config['database'])
            source_cursor = source_conn.cursor()
            
            # Connect to target database
            target_conn = self.connect_database(self.target_config['database'])
            target_cursor = target_conn.cursor()
            
            # Get table schemas from source
            source_cursor.execute("""
                SELECT table_name, column_name, data_type, is_nullable, column_default
                FROM information_schema.columns
                WHERE table_schema = 'public'
                ORDER BY table_name, ordinal_position
            """)
            
            tables = {}
            for row in source_cursor.fetchall():
                table_name, column_name, data_type, is_nullable, column_default = row
                if table_name not in tables:
                    tables[table_name] = []
                tables[table_name].append({
                    'column_name': column_name,
                    'data_type': data_type,
                    'is_nullable': is_nullable,
                    'column_default': column_default
                })
            
            # Create tables in target database
            for table_name, columns in tables.items():
                self.log(f"Creating table: {table_name}")
                
                # Build CREATE TABLE statement
                column_definitions = []
                for col in columns:
                    col_def = f"{col['column_name']} {col['data_type']}"
                    if col['is_nullable'] == 'NO':
                        col_def += " NOT NULL"
                    if col['column_default']:
                        col_def += f" DEFAULT {col['column_default']}"
                    column_definitions.append(col_def)
                
                create_table_sql = f"""
                    CREATE TABLE IF NOT EXISTS {table_name} (
                        {', '.join(column_definitions)}
                    )
                """
                
                target_cursor.execute(create_table_sql)
                target_conn.commit()
            
            # Get indexes from source
            source_cursor.execute("""
                SELECT indexname, indexdef
                FROM pg_indexes
                WHERE schemaname = 'public'
            """)
            
            for index_name, index_def in source_cursor.fetchall():
                self.log(f"Creating index: {index_name}")
                target_cursor.execute(index_def)
                target_conn.commit()
            
            source_cursor.close()
            source_conn.close()
            target_cursor.close()
            target_conn.close()
            
            self.log("Database schema migration completed successfully")
            
        except Exception as e:
            self.log(f"Database schema migration failed: {e}", "ERROR")
            raise
    
    def migrate_database_data(self):
        """Migrate data from ECS to EKS database"""
        self.log("Starting database data migration...")
        
        try:
            # Connect to source database
            source_conn = self.connect_database(self.source_config['database'])
            source_cursor = source_conn.cursor()
            
            # Connect to target database
            target_conn = self.connect_database(self.target_config['database'])
            target_cursor = target_conn.cursor()
            
            # Get all tables
            source_cursor.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_type = 'BASE TABLE'
            """)
            
            tables = [row[0] for row in source_cursor.fetchall()]
            
            for table_name in tables:
                self.log(f"Migrating data from table: {table_name}")
                
                # Get row count
                source_cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
                row_count = source_cursor.fetchone()[0]
                
                if row_count == 0:
                    self.log(f"Table {table_name} is empty, skipping...")
                    continue
                
                # Get all data from source table
                source_cursor.execute(f"SELECT * FROM {table_name}")
                rows = source_cursor.fetchall()
                
                # Get column names
                source_cursor.execute(f"""
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_name = '{table_name}'
                    AND table_schema = 'public'
                    ORDER BY ordinal_position
                """)
                columns = [row[0] for row in source_cursor.fetchall()]
                
                # Insert data into target table
                placeholders = ', '.join(['%s'] * len(columns))
                insert_sql = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
                
                target_cursor.executemany(insert_sql, rows)
                target_conn.commit()
                
                self.log(f"Migrated {len(rows)} rows from {table_name}")
            
            source_cursor.close()
            source_conn.close()
            target_cursor.close()
            target_conn.close()
            
            self.log("Database data migration completed successfully")
            
        except Exception as e:
            self.log(f"Database data migration failed: {e}", "ERROR")
            raise
    
    def migrate_redis_data(self):
        """Migrate data from ECS to EKS Redis"""
        self.log("Starting Redis data migration...")
        
        try:
            # Connect to source Redis
            source_redis = self.connect_redis(self.source_config['redis'])
            
            # Connect to target Redis
            target_redis = self.connect_redis(self.target_config['redis'])
            
            # Get all keys from source
            keys = source_redis.keys('*')
            self.log(f"Found {len(keys)} keys in source Redis")
            
            migrated_count = 0
            for key in keys:
                try:
                    # Get key type
                    key_type = source_redis.type(key)
                    
                    if key_type == 'string':
                        value = source_redis.get(key)
                        ttl = source_redis.ttl(key)
                        target_redis.set(key, value)
                        if ttl > 0:
                            target_redis.expire(key, ttl)
                    
                    elif key_type == 'hash':
                        hash_data = source_redis.hgetall(key)
                        target_redis.hmset(key, hash_data)
                        ttl = source_redis.ttl(key)
                        if ttl > 0:
                            target_redis.expire(key, ttl)
                    
                    elif key_type == 'list':
                        list_data = source_redis.lrange(key, 0, -1)
                        for item in list_data:
                            target_redis.rpush(key, item)
                        ttl = source_redis.ttl(key)
                        if ttl > 0:
                            target_redis.expire(key, ttl)
                    
                    elif key_type == 'set':
                        set_data = source_redis.smembers(key)
                        for item in set_data:
                            target_redis.sadd(key, item)
                        ttl = source_redis.ttl(key)
                        if ttl > 0:
                            target_redis.expire(key, ttl)
                    
                    elif key_type == 'zset':
                        zset_data = source_redis.zrange(key, 0, -1, withscores=True)
                        for item, score in zset_data:
                            target_redis.zadd(key, {item: score})
                        ttl = source_redis.ttl(key)
                        if ttl > 0:
                            target_redis.expire(key, ttl)
                    
                    migrated_count += 1
                    
                except Exception as e:
                    self.log(f"Failed to migrate key {key}: {e}", "WARNING")
                    continue
            
            self.log(f"Migrated {migrated_count} keys from Redis")
            self.log("Redis data migration completed successfully")
            
        except Exception as e:
            self.log(f"Redis data migration failed: {e}", "ERROR")
            raise
    
    def validate_migration(self):
        """Validate that migration was successful"""
        self.log("Starting migration validation...")
        
        try:
            # Validate database
            source_conn = self.connect_database(self.source_config['database'])
            source_cursor = source_conn.cursor()
            
            target_conn = self.connect_database(self.target_config['database'])
            target_cursor = target_conn.cursor()
            
            # Compare table counts
            source_cursor.execute("""
                SELECT table_name, 
                       (xpath('/row/cnt/text()', xml_count))[1]::text::int as row_count
                FROM (
                    SELECT table_name, 
                           query_to_xml(format('select count(*) as cnt from %I.%I', table_schema, table_name), false, true, '') as xml_count
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                    AND table_type = 'BASE TABLE'
                ) t
            """)
            
            source_counts = {row[0]: row[1] for row in source_cursor.fetchall()}
            
            target_cursor.execute("""
                SELECT table_name, 
                       (xpath('/row/cnt/text()', xml_count))[1]::text::int as row_count
                FROM (
                    SELECT table_name, 
                           query_to_xml(format('select count(*) as cnt from %I.%I', table_schema, table_name), false, true, '') as xml_count
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                    AND table_type = 'BASE TABLE'
                ) t
            """)
            
            target_counts = {row[0]: row[1] for row in target_cursor.fetchall()}
            
            # Compare counts
            for table_name, source_count in source_counts.items():
                target_count = target_counts.get(table_name, 0)
                if source_count == target_count:
                    self.log(f"✅ Table {table_name}: {source_count} rows (match)")
                else:
                    self.log(f"❌ Table {table_name}: source={source_count}, target={target_count} (mismatch)", "ERROR")
            
            source_cursor.close()
            source_conn.close()
            target_cursor.close()
            target_conn.close()
            
            # Validate Redis
            source_redis = self.connect_redis(self.source_config['redis'])
            target_redis = self.connect_redis(self.target_config['redis'])
            
            source_keys = set(source_redis.keys('*'))
            target_keys = set(target_redis.keys('*'))
            
            if source_keys == target_keys:
                self.log(f"✅ Redis keys match: {len(source_keys)} keys")
            else:
                missing_keys = source_keys - target_keys
                extra_keys = target_keys - source_keys
                if missing_keys:
                    self.log(f"❌ Missing keys in target: {missing_keys}", "ERROR")
                if extra_keys:
                    self.log(f"❌ Extra keys in target: {extra_keys}", "ERROR")
            
            self.log("Migration validation completed")
            
        except Exception as e:
            self.log(f"Migration validation failed: {e}", "ERROR")
            raise
    
    def save_migration_log(self, filename: str):
        """Save migration log to file"""
        with open(filename, 'w') as f:
            json.dump(self.migration_log, f, indent=2)
        self.log(f"Migration log saved to {filename}")
    
    def run_migration(self):
        """Run the complete migration process"""
        self.log("Starting ECS to EKS data migration...")
        
        try:
            # Migrate database schema
            self.migrate_database_schema()
            
            # Migrate database data
            self.migrate_database_data()
            
            # Migrate Redis data
            self.migrate_redis_data()
            
            # Validate migration
            self.validate_migration()
            
            self.log("Data migration completed successfully!")
            
        except Exception as e:
            self.log(f"Migration failed: {e}", "ERROR")
            raise
        finally:
            # Save migration log
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            log_filename = f"migration_log_{timestamp}.json"
            self.save_migration_log(log_filename)

def main():
    parser = argparse.ArgumentParser(description='Migrate data from ECS to EKS')
    parser.add_argument('--source-config', required=True, help='Source configuration file')
    parser.add_argument('--target-config', required=True, help='Target configuration file')
    parser.add_argument('--schema-only', action='store_true', help='Only migrate schema')
    parser.add_argument('--data-only', action='store_true', help='Only migrate data')
    parser.add_argument('--validate-only', action='store_true', help='Only validate migration')
    
    args = parser.parse_args()
    
    # Load configurations
    with open(args.source_config, 'r') as f:
        source_config = json.load(f)
    
    with open(args.target_config, 'r') as f:
        target_config = json.load(f)
    
    # Create migrator
    migrator = DataMigrator(source_config, target_config)
    
    try:
        if args.schema_only:
            migrator.migrate_database_schema()
        elif args.data_only:
            migrator.migrate_database_data()
            migrator.migrate_redis_data()
        elif args.validate_only:
            migrator.validate_migration()
        else:
            migrator.run_migration()
    except Exception as e:
        print(f"Migration failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
