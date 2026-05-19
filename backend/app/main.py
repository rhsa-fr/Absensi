from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

# Import router dari sub-folder
from app.routers import auth, attendance, leaves, master, users

app = FastAPI(
    title="Sistem Absensi Terintegrasi API",
    description="Backend API untuk Sistem Absensi berbasis Geofence, QR Dinamis, dan Device Binding",
    version="2.0.0",
)

# Konfigurasi CORS (Cross-Origin Resource Sharing)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Pada production, ganti dengan origin spesifik
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pastikan directory uploads terbuat secara otomatis
os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# Mendaftarkan router ke main application
app.include_router(auth.router, prefix="/api/v1")
app.include_router(attendance.router, prefix="/api/v1")
app.include_router(leaves.router, prefix="/api/v1")
app.include_router(master.router, prefix="/api/v1")
app.include_router(users.router, prefix="/api/v1")

@app.get("/")
async def root():
    return {
        "status": "success",
        "message": "Sistem Absensi Terintegrasi API is running!",
        "version": "2.0.0"
    }
