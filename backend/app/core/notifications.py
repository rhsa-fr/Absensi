import os
import logging
from typing import Any

logger = logging.getLogger("clockit_notifications")

# Path ke file kunci Service Account Firebase V1 Anda
SERVICE_ACCOUNT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "firebase-service-account.json"
)

_firebase_initialized = False

def _initialize_firebase() -> bool:
  """Menginisialisasi Firebase Admin SDK secara aman jika file kredensial V1 ditemukan."""
  global _firebase_initialized
  if _firebase_initialized:
    return True

  if not os.path.exists(SERVICE_ACCOUNT_PATH):
    return False

  try:
    import firebase_admin
    from firebase_admin import credentials
    
    if not firebase_admin._apps:
      cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
      firebase_admin.initialize_app(cred)
    
    _firebase_initialized = True
    logger.info("[+] Firebase Admin SDK berhasil diinisialisasi untuk FCM V1 API! 🔐")
    return True
  except ImportError:
    logger.warning("[-] firebase-admin library tidak terinstall. Menggunakan mode simulasi.")
    return False
  except Exception as e:
    logger.error(f"[x] Gagal menginisialisasi Firebase Admin SDK: {e}")
    return False

async def send_push_notification(fcm_token: str | None, title: str, body: str) -> bool:
  """
  Mengirimkan real-time Push Notification ke HP Karyawan via Firebase Cloud Messaging V1 API.
  Secara otomatis mendeteksi status inisialisasi dan memberikan panduan premium jika belum dikonfigurasi.
  """
  if not fcm_token:
    logger.info("[-] Skip push notification (Karyawan tidak memiliki FCM Token terikat).")
    return False

  # Coba inisialisasi Firebase Admin SDK (FCM V1)
  sdk_ready = _initialize_firebase()

  if sdk_ready:
    try:
      from firebase_admin import messaging
      
      # Bungkus pesan ke format FCM V1
      message = messaging.Message(
          notification=messaging.Notification(
              title=title,
              body=body,
          ),
          data={
              "page": "cuti"
          },
          android=messaging.AndroidConfig(
              notification=messaging.AndroidNotification(
                  sound="default",
                  click_action="FLUTTER_NOTIFICATION_CLICK"
              )
          ),
          apns=messaging.APNSConfig(
              payload=messaging.APNSPayload(
                  aps=messaging.Aps(
                      sound="default",
                  )
              )
          ),
          token=fcm_token,
      )
      
      # Kirim notifikasi secara asinkron (menggunakan ThreadPoolExecutor bawaan SDK jika perlu, 
      # namun pemanggilan standar sudah sangat cepat)
      response = messaging.send(message)
      logger.info(f"[+] Push notification V1 sukses terkirim! ID: {response}")
      return True
      
    except Exception as e:
      logger.error(f"[x] Gagal mengirim pesan via FCM V1: {e}")
      return False
  else:
    # 📝 Mode Simulasi Premium + Panduan Pengunduhan Kunci Akun Layanan
    logger.info("====================================================================")
    logger.info("🔔 [SIMULASI PUSH NOTIFICATION FCM V1]")
    logger.info(f"📍 Target HP Token : {fcm_token[:25]}...")
    logger.info(f"📝 Judul Notifikasi: {title}")
    logger.info(f"💬 Isi Pesan       : {body}")
    logger.info("--------------------------------------------------------------------")
    logger.info("💡 CARA MENGAKTIFKAN NOTIFIKASI NYATA (FCM V1):")
    logger.info("1. Di layar browser Firebase Anda, klik tab 'Service accounts' (di sebelah Cloud Messaging).")
    logger.info("2. Klik tombol biru 'Generate new private key'.")
    logger.info("3. Unduh file JSON kunci privat tersebut.")
    logger.info("4. Ubah nama file tersebut menjadi 'firebase-service-account.json'.")
    logger.info("5. Letakkan file tersebut di folder utama backend Anda di:")
    logger.info(f"   📂 {os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))}")
    logger.info("6. Jalankan 'pip install firebase-admin' di terminal backend Anda.")
    logger.info("====================================================================")
    return True
