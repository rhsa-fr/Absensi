import asyncio
from app.db.session import engine
from app.models import Base

async def init_models():
    # Membuat tabel-tabel di database (Hanya digunakan untuk development/prototyping)
    async with engine.begin() as conn:
        # PENTING: Untuk production, gunakan tool migrasi seperti Alembic.
        # drop_all akan MENGHAPUS semua data jika sudah ada (hati-hati!).
        await conn.run_sync(Base.metadata.drop_all) 
        
        print("Menciptakan tabel di database...")
        await conn.run_sync(Base.metadata.create_all)
        print("Selesai! Tabel berhasil dibuat.")

if __name__ == "__main__":
    asyncio.run(init_models())
