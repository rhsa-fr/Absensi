import asyncio
from app.db.session import engine
from sqlalchemy import text

async def reset_device_bindings():
    async with engine.begin() as conn:
        print("[+] Mereset seluruh kaitan perangkat (User Devices)...")
        await conn.execute(text("DELETE FROM user_devices"))
        print("[+] Sukses! Seluruh kaitan perangkat di database berhasil dibersihkan.")
        print("[+] Karyawan kini dapat melakukan Login dan melakukan Silent Auto-Binding otomatis di HP baru mereka! 📱✨")

if __name__ == "__main__":
    asyncio.run(reset_device_bindings())
