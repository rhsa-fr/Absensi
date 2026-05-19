from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Time, Float
from sqlalchemy.orm import relationship, declarative_base
from geoalchemy2 import Geometry
import datetime

Base = declarative_base()

class Role(Base):
    __tablename__ = "roles"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), unique=True, nullable=False)
    
    users = relationship("User", back_populates="role")

class Department(Base):
    __tablename__ = "departments"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, nullable=False)
    
    users = relationship("User", back_populates="department")

class Shift(Base):
    __tablename__ = "shifts"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), nullable=False)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    tolerance_minutes = Column(Integer, default=0)
    
    users = relationship("User", back_populates="shift")

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(100), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(100), nullable=False)
    is_active = Column(Boolean, default=True)
    is_wfh_allowed = Column(Boolean, default=False)
    reset_token = Column(String(100), nullable=True)
    reset_token_expires = Column(DateTime, nullable=True)
    
    role_id = Column(Integer, ForeignKey("roles.id"))
    department_id = Column(Integer, ForeignKey("departments.id"))
    shift_id = Column(Integer, ForeignKey("shifts.id"))
    
    role = relationship("Role", back_populates="users")
    department = relationship("Department", back_populates="users")
    shift = relationship("Shift", back_populates="users")
    devices = relationship("UserDevice", back_populates="user", cascade="all, delete-orphan")
    attendances = relationship("Attendance", back_populates="user")
    leave_balances = relationship("LeaveBalance", back_populates="user")
    leave_requests = relationship("LeaveRequest", back_populates="user")
    notifications = relationship("Notification", back_populates="user", cascade="all, delete-orphan")

class UserDevice(Base):
    __tablename__ = "user_devices"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    device_id = Column(String(255), unique=True, nullable=False)
    device_model = Column(String(100))
    registered_at = Column(DateTime, default=datetime.datetime.utcnow)
    
    user = relationship("User", back_populates="devices")

class Geofence(Base):
    __tablename__ = "geofences"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    # Tipe geometri dari PostGIS (GeoAlchemy2). 
    # SRID 4326 adalah sistem referensi koordinat standar WGS 84 (GPS).
    location = Column(Geometry('POINT', srid=4326), nullable=False)
    radius_meters = Column(Float, nullable=False)
    
    attendances = relationship("Attendance", back_populates="geofence")

class Attendance(Base):
    __tablename__ = "attendances"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    geofence_id = Column(Integer, ForeignKey("geofences.id"), nullable=False)
    device_id = Column(String(255), nullable=False)
    
    scan_time = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    actual_location = Column(Geometry('POINT', srid=4326), nullable=False)
    
    status = Column(String(50)) # e.g. "Tepat Waktu", "Terlambat"
    is_valid = Column(Boolean, default=True)
    
    user = relationship("User", back_populates="attendances")
    geofence = relationship("Geofence", back_populates="attendances")

class LeaveBalance(Base):
    __tablename__ = "leave_balances"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    year = Column(Integer, nullable=False)
    total_quota = Column(Integer, nullable=False)
    used_quota = Column(Integer, default=0)
    
    user = relationship("User", back_populates="leave_balances")

class LeaveRequest(Base):
    __tablename__ = "leave_requests"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    start_date = Column(DateTime, nullable=False)
    end_date = Column(DateTime, nullable=False)
    reason = Column(String(255))
    document_url = Column(String(255))
    status = Column(String(50), default="Pending") # Pending, Approved, Rejected
    
    user = relationship("User", back_populates="leave_requests")

class Notification(Base):
    __tablename__ = "notifications"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    title = Column(String(100), nullable=False)
    message = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    is_read = Column(Boolean, default=False)
    
    user = relationship("User", back_populates="notifications")
