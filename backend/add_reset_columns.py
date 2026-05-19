import asyncio
import sys
import os
from sqlalchemy import text

# Add backend directory to python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.db.session import engine

async def add_columns():
    async with engine.begin() as conn:
        print("[INFO] Menambahkan kolom reset_token ke tabel users...")
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_token VARCHAR(100) NULL;"))
        
        print("[INFO] Menambahkan kolom reset_token_expires ke tabel users...")
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_token_expires TIMESTAMP NULL;"))
        
        print("[SUCCESS] Migrasi kolom berhasil selesai!")

if __name__ == "__main__":
    asyncio.run(add_columns())
