from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.core.config import settings
from collections.abc import AsyncGenerator

# Engine asynchronous SQLAlchemy menggunakan asyncpg
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,          # Set True saat debugging
    future=True,
    pool_pre_ping=True   # Pengecekan koneksi terputus secara otomatis
)

# Pembuat session asinkron
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)

# Dependency FastAPI untuk memanggil session database
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
