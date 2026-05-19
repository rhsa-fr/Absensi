import asyncio
import sys
import os

# Menambahkan directory backend ke python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.db.session import engine
from app.models import Base

async def create_new_tables():
    async with engine.begin() as conn:
        print("[INFO] Memeriksa dan membuat tabel baru yang belum ada di database...")
        await conn.run_sync(Base.metadata.create_all)
        print("[SUCCESS] Selesai! Tabel baru berhasil dibuat.")

if __name__ == "__main__":
    asyncio.run(create_new_tables())
