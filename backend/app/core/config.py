import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Sistem Absensi Terintegrasi"
    VERSION: str = "2.0.0"
    
    # Ganti dengan connection string aslinya untuk PostgreSQL + PostGIS (menggunakan asyncpg)
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql+asyncpg://postgres:password@localhost:5432/absen_db")
    
    SECRET_KEY: str = os.getenv("SECRET_KEY", "super-secret-key-enterprise-12345")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440 # 24 jam

    # SMTP Configuration for Real Emails
    SMTP_SERVER: str = os.getenv("SMTP_SERVER", "smtp.gmail.com")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USERNAME: str = os.getenv("SMTP_USERNAME", "")
    SMTP_PASSWORD: str = os.getenv("SMTP_PASSWORD", "")
    SMTP_FROM: str = os.getenv("SMTP_FROM", "noreply@clockit.com")

    class Config:
        env_file = ".env"

settings = Settings()
